"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.validate = exports.getAnnotationArgs = exports.isOpcodeError = void 0;
const utils_1 = require("solidity-ast/utils");
const ast_dereferencer_1 = require("../ast-dereferencer");
const is_nullish_1 = require("../utils/is-nullish");
const function_1 = require("../utils/function");
const version_1 = require("../version");
const link_refs_1 = require("../link-refs");
const extract_1 = require("../storage/extract");
const errorKinds = [
    'state-variable-assignment',
    'state-variable-immutable',
    'external-library-linking',
    'struct-definition',
    'enum-definition',
    'constructor',
    'delegatecall',
    'selfdestruct',
    'missing-public-upgradeto',
];
const OPCODES = {
    delegatecall: {
        kind: 'delegatecall',
        pattern: /^t_function_baredelegatecall_/,
    },
    selfdestruct: {
        kind: 'selfdestruct',
        pattern: /^t_function_selfdestruct_/,
    },
};
function isOpcodeError(error) {
    return error.kind === 'delegatecall' || error.kind === 'selfdestruct';
}
exports.isOpcodeError = isOpcodeError;
function* execall(re, text) {
    re = new RegExp(re, re.flags + (re.sticky ? '' : 'y'));
    while (true) {
        const match = re.exec(text);
        if (match && match[0] !== '') {
            yield match;
        }
        else {
            break;
        }
    }
}
function getAllowed(node, reachable) {
    if ('documentation' in node) {
        const tag = `oz-upgrades-unsafe-allow${reachable ? '-reachable' : ''}`;
        const doc = typeof node.documentation === 'string' ? node.documentation : node.documentation?.text ?? '';
        return getAnnotationArgs(doc, tag);
    }
    else {
        return [];
    }
}
/**
 * Get args from the doc string matching the given tag
 */
function getAnnotationArgs(doc, tag) {
    const result = [];
    for (const { groups } of execall(/^\s*(?:@(?<title>\w+)(?::(?<tag>[a-z][a-z-]*))? )?(?<args>(?:(?!^\s*@\w+)[^])*)/m, doc)) {
        if (groups && groups.title === 'custom' && groups.tag === tag) {
            const trimmedArgs = groups.args.trim();
            if (trimmedArgs.length > 0) {
                result.push(...trimmedArgs.split(/\s+/));
            }
        }
    }
    result.forEach(arg => {
        if (!errorKinds.includes(arg)) {
            throw new Error(`NatSpec: ${tag} argument not recognized: ${arg}`);
        }
    });
    return result;
}
exports.getAnnotationArgs = getAnnotationArgs;
function skipCheckReachable(error, node) {
    return getAllowed(node, true).includes(error);
}
function skipCheck(error, node) {
    // skip both allow and allow-reachable errors in the lexical scope
    return getAllowed(node, false).includes(error) || getAllowed(node, true).includes(error);
}
function getFullyQualifiedName(source, contractName) {
    return `${source}:${contractName}`;
}
function validate(solcOutput, decodeSrc, solcVersion) {
    const validation = {};
    const fromId = {};
    const inheritIds = {};
    const libraryIds = {};
    const deref = (0, ast_dereferencer_1.astDereferencer)(solcOutput);
    const delegateCallCache = initOpcodeCache();
    const selfDestructCache = initOpcodeCache();
    for (const source in solcOutput.contracts) {
        for (const contractName in solcOutput.contracts[source]) {
            const bytecode = solcOutput.contracts[source][contractName].evm.bytecode;
            const version = bytecode.object === '' ? undefined : (0, version_1.getVersion)(bytecode.object);
            const linkReferences = (0, link_refs_1.extractLinkReferences)(bytecode);
            validation[getFullyQualifiedName(source, contractName)] = {
                src: contractName,
                version,
                inherit: [],
                libraries: [],
                methods: [],
                linkReferences,
                errors: [],
                layout: {
                    storage: [],
                    types: {},
                },
                solcVersion,
            };
        }
        for (const contractDef of (0, utils_1.findAll)('ContractDefinition', solcOutput.sources[source].ast)) {
            const key = getFullyQualifiedName(source, contractDef.name);
            fromId[contractDef.id] = key;
            // May be undefined in case of duplicate contract names in Truffle
            const bytecode = solcOutput.contracts[source][contractDef.name]?.evm.bytecode;
            if (key in validation && bytecode !== undefined) {
                inheritIds[key] = contractDef.linearizedBaseContracts.slice(1);
                libraryIds[key] = getReferencedLibraryIds(contractDef);
                validation[key].src = decodeSrc(contractDef);
                validation[key].errors = [
                    ...getConstructorErrors(contractDef, decodeSrc),
                    ...getOpcodeErrors(contractDef, deref, decodeSrc, delegateCallCache, selfDestructCache),
                    ...getStateVariableErrors(contractDef, decodeSrc),
                    // TODO: add linked libraries support
                    // https://github.com/OpenZeppelin/openzeppelin-upgrades/issues/52
                    ...getLinkingErrors(contractDef, bytecode),
                ];
                validation[key].layout = (0, extract_1.extractStorageLayout)(contractDef, decodeSrc, deref, solcOutput.contracts[source][contractDef.name].storageLayout);
                validation[key].methods = [...(0, utils_1.findAll)('FunctionDefinition', contractDef)]
                    .filter(fnDef => ['external', 'public'].includes(fnDef.visibility))
                    .map(fnDef => (0, function_1.getFunctionSignature)(fnDef, deref));
            }
        }
    }
    for (const key in inheritIds) {
        validation[key].inherit = inheritIds[key].map(id => fromId[id]);
    }
    for (const key in libraryIds) {
        validation[key].libraries = libraryIds[key].map(id => fromId[id]);
    }
    return validation;
}
exports.validate = validate;
function* getConstructorErrors(contractDef, decodeSrc) {
    for (const fnDef of (0, utils_1.findAll)('FunctionDefinition', contractDef, node => skipCheck('constructor', node))) {
        if (fnDef.kind === 'constructor' && ((fnDef.body?.statements?.length ?? 0) > 0 || fnDef.modifiers.length > 0)) {
            yield {
                kind: 'constructor',
                contract: contractDef.name,
                src: decodeSrc(fnDef),
            };
        }
    }
}
function initOpcodeCache() {
    return {
        mainContractErrors: new Map(),
        inheritedContractErrors: new Map(),
    };
}
function* getOpcodeErrors(contractDef, deref, decodeSrc, delegateCallCache, selfDestructCache) {
    yield* getContractOpcodeErrors(contractDef, deref, decodeSrc, OPCODES.delegatecall, 'main', delegateCallCache);
    yield* getContractOpcodeErrors(contractDef, deref, decodeSrc, OPCODES.selfdestruct, 'main', selfDestructCache);
}
function* getContractOpcodeErrors(contractDef, deref, decodeSrc, opcode, scope, cache) {
    const cached = getCachedOpcodes(contractDef.id, scope, cache);
    if (cached !== undefined) {
        yield* cached;
    }
    else {
        const errors = [];
        setCachedOpcodes(contractDef.id, scope, cache, errors);
        errors.push(...getFunctionOpcodeErrors(contractDef, deref, decodeSrc, opcode, scope, cache), ...getInheritedContractOpcodeErrors(contractDef, deref, decodeSrc, opcode, cache));
        yield* errors;
    }
}
function getCachedOpcodes(key, scope, cache) {
    return scope === 'main' ? cache.mainContractErrors.get(key) : cache.inheritedContractErrors.get(key);
}
function* getFunctionOpcodeErrors(contractOrFunctionDef, deref, decodeSrc, opcode, scope, cache) {
    const parentContractDef = getParentDefinition(deref, contractOrFunctionDef);
    if (parentContractDef === undefined || !skipCheck(opcode.kind, parentContractDef)) {
        yield* getDirectFunctionOpcodeErrors(contractOrFunctionDef, decodeSrc, opcode, scope);
    }
    if (parentContractDef === undefined || !skipCheckReachable(opcode.kind, parentContractDef)) {
        yield* getReferencedFunctionOpcodeErrors(contractOrFunctionDef, deref, decodeSrc, opcode, scope, cache);
    }
}
function* getDirectFunctionOpcodeErrors(contractOrFunctionDef, decodeSrc, opcode, scope) {
    for (const fnCall of (0, utils_1.findAll)('FunctionCall', contractOrFunctionDef, node => skipCheck(opcode.kind, node) || (scope === 'inherited' && isInternalFunction(node)))) {
        const fn = fnCall.expression;
        if (fn.typeDescriptions.typeIdentifier?.match(opcode.pattern)) {
            yield {
                kind: opcode.kind,
                src: decodeSrc(fnCall),
            };
        }
    }
}
function* getReferencedFunctionOpcodeErrors(contractOrFunctionDef, deref, decodeSrc, opcode, scope, cache) {
    for (const fnCall of (0, utils_1.findAll)('FunctionCall', contractOrFunctionDef, node => skipCheckReachable(opcode.kind, node) || (scope === 'inherited' && isInternalFunction(node)))) {
        const fn = fnCall.expression;
        if ('referencedDeclaration' in fn && fn.referencedDeclaration && fn.referencedDeclaration > 0) {
            // non-positive references refer to built-in functions
            const referencedNode = tryDerefFunction(deref, fn.referencedDeclaration);
            if (referencedNode !== undefined) {
                const cached = getCachedOpcodes(referencedNode.id, scope, cache);
                if (cached !== undefined) {
                    yield* cached;
                }
                else {
                    const errors = [];
                    setCachedOpcodes(referencedNode.id, scope, cache, errors);
                    errors.push(...getFunctionOpcodeErrors(referencedNode, deref, decodeSrc, opcode, scope, cache));
                    yield* errors;
                }
            }
        }
    }
}
function setCachedOpcodes(key, scope, cache, errors) {
    if (scope === 'main') {
        cache.mainContractErrors.set(key, errors);
    }
    else {
        cache.inheritedContractErrors.set(key, errors);
    }
}
function tryDerefFunction(deref, referencedDeclaration) {
    try {
        return deref(['FunctionDefinition'], referencedDeclaration);
    }
    catch (e) {
        if (!e.message.includes('No node with id')) {
            throw e;
        }
    }
}
function* getInheritedContractOpcodeErrors(contractDef, deref, decodeSrc, opcode, cache) {
    if (!skipCheckReachable(opcode.kind, contractDef)) {
        for (const base of contractDef.baseContracts) {
            const referencedContract = deref('ContractDefinition', base.baseName.referencedDeclaration);
            yield* getContractOpcodeErrors(referencedContract, deref, decodeSrc, opcode, 'inherited', cache);
        }
    }
}
function getParentDefinition(deref, contractOrFunctionDef) {
    const parentNode = deref(['ContractDefinition', 'SourceUnit'], contractOrFunctionDef.scope);
    if (parentNode.nodeType === 'ContractDefinition') {
        return parentNode;
    }
}
function isInternalFunction(node) {
    return (node.nodeType === 'FunctionDefinition' &&
        node.kind !== 'constructor' && // do not consider constructors as internal, because they are always called by children contracts' constructors
        (node.visibility === 'internal' || node.visibility === 'private'));
}
function* getStateVariableErrors(contractDef, decodeSrc) {
    for (const varDecl of contractDef.nodes) {
        if ((0, utils_1.isNodeType)('VariableDeclaration', varDecl)) {
            if (!varDecl.constant && !(0, is_nullish_1.isNullish)(varDecl.value)) {
                if (!skipCheck('state-variable-assignment', contractDef) && !skipCheck('state-variable-assignment', varDecl)) {
                    yield {
                        kind: 'state-variable-assignment',
                        name: varDecl.name,
                        src: decodeSrc(varDecl),
                    };
                }
            }
            if (varDecl.mutability === 'immutable') {
                if (!skipCheck('state-variable-immutable', contractDef) && !skipCheck('state-variable-immutable', varDecl)) {
                    yield {
                        kind: 'state-variable-immutable',
                        name: varDecl.name,
                        src: decodeSrc(varDecl),
                    };
                }
            }
        }
    }
}
function getReferencedLibraryIds(contractDef) {
    const implicitUsage = [...(0, utils_1.findAll)('UsingForDirective', contractDef)]
        .map(usingForDirective => {
        if (usingForDirective.libraryName !== undefined) {
            return usingForDirective.libraryName.referencedDeclaration;
        }
        else if (usingForDirective.functionList !== undefined) {
            return [];
        }
        else {
            throw new Error('Broken invariant: either UsingForDirective.libraryName or UsingForDirective.functionList should be defined');
        }
    })
        .flat();
    const explicitUsage = [...(0, utils_1.findAll)('Identifier', contractDef)]
        .filter(identifier => identifier.typeDescriptions.typeString?.match(/^type\(library/))
        .map(identifier => {
        if ((0, is_nullish_1.isNullish)(identifier.referencedDeclaration)) {
            throw new Error('Broken invariant: Identifier.referencedDeclaration should not be null');
        }
        return identifier.referencedDeclaration;
    });
    return [...new Set(implicitUsage.concat(explicitUsage))];
}
function* getLinkingErrors(contractDef, bytecode) {
    const { linkReferences } = bytecode;
    for (const source of Object.keys(linkReferences)) {
        for (const libName of Object.keys(linkReferences[source])) {
            if (!skipCheck('external-library-linking', contractDef)) {
                yield {
                    kind: 'external-library-linking',
                    name: libName,
                    src: source,
                };
            }
        }
    }
}
//# sourceMappingURL=run.js.map