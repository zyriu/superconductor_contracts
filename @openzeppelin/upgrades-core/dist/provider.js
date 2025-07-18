"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isReceiptSuccessful = exports.isDevelopmentNetwork = exports.networkNames = exports.getTransactionReceipt = exports.getTransactionByHash = exports.isEmpty = exports.hasCode = exports.call = exports.getCode = exports.getStorageAt = exports.getHardhatMetadata = exports.getClientVersion = exports.getChainId = exports.getNetworkId = void 0;
async function getNetworkId(provider) {
    return provider.send('net_version', []);
}
exports.getNetworkId = getNetworkId;
async function getChainId(provider) {
    const id = await provider.send('eth_chainId', []);
    return parseInt(id.replace(/^0x/, ''), 16);
}
exports.getChainId = getChainId;
async function getClientVersion(provider) {
    return provider.send('web3_clientVersion', []);
}
exports.getClientVersion = getClientVersion;
/**
 * Gets Hardhat metadata when used with Hardhat 2.12.3 or later.
 * The underlying provider will throw an error if this RPC method is not available.
 */
async function getHardhatMetadata(provider) {
    return provider.send('hardhat_metadata', []);
}
exports.getHardhatMetadata = getHardhatMetadata;
async function getStorageAt(provider, address, position, block = 'latest') {
    const storage = await provider.send('eth_getStorageAt', [address, position, block]);
    const padded = storage.replace(/^0x/, '').padStart(64, '0');
    return '0x' + padded;
}
exports.getStorageAt = getStorageAt;
async function getCode(provider, address, block = 'latest') {
    return provider.send('eth_getCode', [address, block]);
}
exports.getCode = getCode;
async function call(provider, address, data, block = 'latest') {
    return provider.send('eth_call', [
        {
            to: address,
            data: data,
        },
        block,
    ]);
}
exports.call = call;
async function hasCode(provider, address, block) {
    const code = await getCode(provider, address, block);
    return !isEmpty(code);
}
exports.hasCode = hasCode;
function isEmpty(code) {
    return code.replace(/^0x/, '') === '';
}
exports.isEmpty = isEmpty;
async function getTransactionByHash(provider, txHash) {
    return provider.send('eth_getTransactionByHash', [txHash]);
}
exports.getTransactionByHash = getTransactionByHash;
async function getTransactionReceipt(provider, txHash) {
    const receipt = await provider.send('eth_getTransactionReceipt', [txHash]);
    if (receipt?.status) {
        receipt.status = receipt.status.match(/^0x0+$/) ? '0x0' : receipt.status.replace(/^0x0+/, '0x');
    }
    return receipt;
}
exports.getTransactionReceipt = getTransactionReceipt;
exports.networkNames = Object.freeze({
    1: 'mainnet',
    2: 'morden',
    3: 'ropsten',
    4: 'rinkeby',
    5: 'goerli',
    10: 'optimism',
    42: 'kovan',
    56: 'bsc',
    97: 'bsc-testnet',
    137: 'polygon',
    420: 'optimism-goerli',
    80001: 'polygon-mumbai',
    43113: 'avalanche-fuji',
    43114: 'avalanche',
    42220: 'celo',
    44787: 'celo-alfajores',
});
async function isDevelopmentNetwork(provider) {
    const chainId = await getChainId(provider);
    //  1337 => ganache and geth --dev
    // 31337 => hardhat network
    if (chainId === 1337 || chainId === 31337) {
        return true;
    }
    else {
        const clientVersion = await getClientVersion(provider);
        const [name] = clientVersion.split('/', 1);
        return name === 'HardhatNetwork' || name === 'EthereumJS TestRPC' || name === 'anvil';
    }
}
exports.isDevelopmentNetwork = isDevelopmentNetwork;
function isReceiptSuccessful(receipt) {
    return receipt.status === '0x1';
}
exports.isReceiptSuccessful = isReceiptSuccessful;
//# sourceMappingURL=provider.js.map