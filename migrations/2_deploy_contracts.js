
const fNFTBond = artifacts.require('fNFTBond')
const BondManager = artifacts.require('BondManager')

module.exports = function(deployer) {
    deployer.deploy(fNFTBond, "d3hfF93udM3nc", "xm48f")
}
