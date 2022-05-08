
const fNFTBond = artifacts.require('fNFTBond')
const BondManager = artifacts.require('BondManager')
const ERC20 = artifacts.require('ERC20')
const StableJoeStaking = artifacts.require('StableJoeStaking.sol')
const VeERC20 = artifacts.require('VeJoeToken.sol')
const VeJoeStaking = artifacts.require('VeJoeStaking.sol')

const FrankTreasury = artifacts.require('FrankTreasury.sol')

module.exports = async (deployer) => {
    

    //await deployer.deploy(FrankTreasury)


    
    await deployer.deploy(fNFTBond, "fNFT Bond", "fNFTB")
    //await deployer.deploy(VeJoeStaking, "0x1217686124AA11323cC389a8BC39C170D665370b", "0x292b07689426863b7eB47e2304e6E6Aa8B55DBDB", "3170979198376", "3170979198376", "5", "1296000", "10000")
    await deployer.deploy(BondManager, fNFTBond.address, "0x1217686124AA11323cC389a8BC39C170D665370b", "0xDa393A9dDeb4609673CEB3deFE7Dda7116247510")

    const bond = await fNFTBond.deployed()
    const manager = await BondManager.deployed()

    await bond.transferOwnership(BondManager.address)
    await manager.linkBondManager()

    const treasury = await FrankTreasury.deployed()

    await treasury.setBondManager(BondManager.address)

}
