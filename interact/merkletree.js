const { MerkleTree } = require('merkletreejs')
const keccak256 = require('keccak256')

const addresses = [
    "0xb3304A14F01Cb5C22E6f5E9fd55b6b6c826e8cc7",
    "0xb3304A14F01Cb5C22E6f5E9fd55b6b6c826e8cc7s",
]

const leafNodes = addresses.map(addr => keccak256(addr))
const tree = new MerkleTree(leafNodes, keccak256, { sortPairs: true })
console.log(tree.toString())

const proof = tree.getHexProof(keccak256("0xb3304A14F01Cb5C22E6f5E9fd55b6b6c826e8cc7"))

console.log(proof)