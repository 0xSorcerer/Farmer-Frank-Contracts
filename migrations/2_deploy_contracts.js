
const fNFTBond = artifacts.require('fNFTBond')
const BondManager = artifacts.require('BondManager')

module.exports = function(deployer) {
    deployer.deploy(fNFTBond, "fNFT Bond", "fNFTB")
}
