
const fNFTBond = artifacts.require('fNFTBond')
const BondManager = artifacts.require('BondManager')
const ERC20 = artifacts.require('ERC20')
const StableJoeStaking = artifacts.require('StableJoeStaking.sol')
const VeERC20 = artifacts.require('VeJoeToken.sol')
const VeJoeStaking = artifacts.require('VeJoeStaking.sol')

const FrankTreasury = artifacts.require('FrankTreasury.sol')

module.exports = async (deployer) => {
    /*
    await deployer.deploy(fNFTBond, "fNFT Bond", "fNFTB")
    //await deployer.deploy(VeJoeStaking, "0x1217686124AA11323cC389a8BC39C170D665370b", "0x292b07689426863b7eB47e2304e6E6Aa8B55DBDB", "3170979198376", "3170979198376", "5", "1296000", "10000")
    await deployer.deploy(BondManager, fNFTBond.address, "0x1217686124AA11323cC389a8BC39C170D665370b", "0xB7271Ee9EED17A645Bf244f8aB3AdD7FD2186F64")

    const bond = await fNFTBond.deployed()
    const manager = await BondManager.deployed()

    await bond.transferOwnership(BondManager.address)
    await manager.linkBondManager()
    */

    await deployer.deploy(FrankTreasury)

    const treasury = await FrankTreasury.deployed()

    await treasury.setBondManager("0xb561A37c55B98e77f48ae639C88D729337558c0D")

}
