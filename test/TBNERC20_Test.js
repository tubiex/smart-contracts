const TBNERC20 = artifacts.require('./TBNERC20');
const assert = require("chai").assert;
require('chai')
    .use(require('chai-as-promised'))
    .should();


contract('TBN_ERC20', function (accounts) {
    /**
     * Global variables 
     */

    let ecr20Contract;

    /**
     * GLobal Constant 
     */
    const WEI = 10e18
    const TOTAL_SUPPLY = 380000000 * WEI;
    const OWNER = accounts[1];
    
    describe('Basic ERC20 functionalities', function () {
        it('Should throw error for incorrect parameters', async function () {
            try {
                ecr20Contract = await TBNERC20.new()
            } catch (error) {
                console.log("Incorrect parameters")
            }
        })

        before('Should deploy TBNERC20 contract ', async function () {
            ecr20Contract = await TBNERC20.new(TOTAL_SUPPLY, "Tubiex Network Token", "TBN", 18, {from: OWNER});
        })

        it('Owner should be the recoverer and fundkeeper', async function() {
            let isfundkeeper = await ecr20Contract.isFundkeeper(OWNER) 
            assert.equal(isfundkeeper,true,"Fundkeeper is the owner")
            let isRecoverer = await ecr20Contract.isRecoverer(OWNER) 
            assert.equal(isRecoverer,true,"Recoverer is the owner")
        })

        it('Should assign total supply, token name and decimal point', async function() {
            let totalSupply = await ecr20Contract.totalSupply()
            assert.equal(totalSupply.toNumber(),TOTAL_SUPPLY,"TotalSupply should be equal ")
            let symbol = await ecr20Contract.symbol()
            assert.equal(symbol,"TBN","symbol should be equal ")
            let decimals = await ecr20Contract.decimals()
            assert.equal(decimals.toNumber(),18,"Token decimal should be equal ")
        })

        it('Should mint total supply to the fundkeeper', async function() {
            let balance = await ecr20Contract.balanceOf(OWNER);
            assert.equal(balance.toNumber(),TOTAL_SUPPLY,"Should mint total supply to the fundkeeper")
        })

        it('Should renounce minter after minting', async function() {
            let isMinter = await ecr20Contract.isMinter(OWNER);
            assert.equal(isMinter,false,"Minter should be renounced after deployment")
        })
        
        it('Should throw error when the minter tries to mint after deployment', async function() {
            await ecr20Contract.mint(accounts[3],TOTAL_SUPPLY).should.be.rejected;
        })
        
        it('Should throw error when ether sent to the erc20 contract', async function() {
            try {
                await web3.eth.sendTransaction({from: accounts[3],to:ecr20Contract.address, value:web3.toWei(66, "ether")})
            } catch (error) {
                //Do nothing
            }
        })

        //recover is pending 
        it('Should be able to recover tokens sent to this contract', async function() {
            let testContract = await TBNERC20.new(TOTAL_SUPPLY, "Test Token", "TEST", 18, {from: OWNER});
            await testContract.transfer(ecr20Contract.address,TOTAL_SUPPLY,{from: OWNER});
            let erc20balance = await ecr20Contract.balanceOf(ecr20Contract.address);
        })
        
        it('Owner Should be able to transfer tokens ', async function() {
            await ecr20Contract.transfer(accounts[3], TOTAL_SUPPLY/2, {from:OWNER})
            let erc20balance = await ecr20Contract.balanceOf(accounts[3]);
            assert.equal(erc20balance.toNumber(), TOTAL_SUPPLY/2, "Account3 token balance should be equal to totalSupply")
        })


    })
})

