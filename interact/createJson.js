const HDWalletProvider = require('@truffle/hdwallet-provider')
const env = require('../.env.json')

const Web3 = require('web3')
const web3 = new Web3(new HDWalletProvider(env.KOVAN_KEY, "https://kovan.infura.io/v3/c63564d5fad8416ba9fddb16007a737c"))

var fs = require('fs');

const BondManagerABI = require('../build/contracts/BondManager.json').abi;

const init = async () => {

    const c = new web3.eth.Contract(BondManagerABI, "0xb876295777fFde1804C62204283c7076ab31BFC2")
    const levels = await c.methods.getActiveBondLevels().call();


    const baseIPFS = "ipfs://QmdDBWXJrKiBoxRizhUmv8BCFadHFBzgbzUe5iUmagBB7i";

    

    
    for(var i = 0; i < levels.length; i++) {

    

        const data = await c.methods.getBondLevel(levels[i]).call();

        const file = {
            name: "Farmer Frank JOE NFT Bond: " + data.name,
            description: "Representation of ownership over the Farmer Frank protocol.",
            image: baseIPFS + "/" + levels[i] + ".png",
            attributes: [
                {
                    trait_type: "Bond Level",
                    value: data.name
                },
                {
                    trait_type: "Bond Base Price",
                    value: data.price.substring(0, data.price.length - 18) + " JOE",
                },
                {
                    trait_type: "Bond Weight",
                    value: (new Number(data.weight) / 100).toFixed(2) + "x",
                },
                {
                    trait_type: "Bond Starting Unweighted Shares",
                    value: data.price.substring(0, data.price.length - 18),
                },
                {
                    trait_type: "Bond Starting Weighted Shares",
                    value: (data.price.substring(0, data.price.length - 18) * (new Number(data.weight) / 100)).toString(),
                },
                {
                    trait_type: "Bond XP",
                    value: data.price.substring(0, data.price.length - 18),
                }
            ]
        }

        await fs.writeFileSync('../metadata/' + levels[i], JSON.stringify(file))
    }
    

    //console.log(web3.eth.abi.encodeFunctionSignature('harvest()'))
    


}

init()

