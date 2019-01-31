
const TBNERC20 = artifacts.require('./TBNERC20');
const Airdrop = artifacts.require('./Airdrop');
const Crowdsale = artifacts.require('./TBNCrowdsale');
const BigNumber = require('bignumber.js');
const assert = require("chai").assert;
require('chai')
    .use(require('chai-as-promised'))
    .should();

/* Web 3 Objects */
const Web3 = require('web3');
const web3 = new Web3('http://localhost:7545');

contract('airdrop', function (accounts) {
    /**
     * Global variables
     */
    let erc20Contract;
    let airdropContract;
    let crowdsaleContract;
    let airdropTokens;
    let distributedTokens;
    let totalSupply;

    /**
     * Global Constants
     */
    const WEI = 1e18;
    const claimPeriod = 30;
    const TOTAL_SUPPLY = 380000000 * WEI;
    const onePerc = 0.01;


    /**
     * Airdrop constants
     */
    const airdropDeployed = 0;
    const airdrop = 1;
    const airdropEnded = 2;
    const nullAddress = "0x000000000000000000"
    const owner = accounts[0]
    

    //Crowdsale const
    const intervals = 10;
    const guaranteedIntervals = 5;
    const hiddenCap = '10000000000000000000000000';
    const secretNumber = 1234;
    const ethPrice = 100 * 1e18  // 100 USD in 18 decimal point
    const newEthPrice = 10 * 1e18  // 10 USD in decimal point
    const floor = 1.0 * 1e17;
    const ceiling =  2 * 1e18;
    const reserveStart = 1 * 1e18;
    const crowdSaleAllocation = 10000 * WEI;

    describe('Aidrop Token Initialisation {fundkeeper}', async function () {
        before('Should return the deployed erc20 contract instance ', async function () {
            erc20Contract = await TBNERC20.new(TOTAL_SUPPLY, "Tubiex Network Token", "TBN", 18);
        })
        
        it('Should deploy a crowdsale contract ', async function(){
            hiddenCapHash = web3.utils.soliditySha3(hiddenCap,secretNumber)
            crowdsaleContract = await Crowdsale.new(erc20Contract.address,intervals,guaranteedIntervals,hiddenCapHash);            
        })

        it('Should approve for crowdsale contract', async function() {
            await erc20Contract.approve(crowdsaleContract.address, crowdSaleAllocation);
            let allowance = await erc20Contract.allowance(accounts[0], crowdsaleContract.address);
            assert.equal(allowance.toNumber(), crowdSaleAllocation, "Allowance should be equal to allocation")
        })

        it(' Should initialize crowdsale contract', async function() {
            await crowdsaleContract.initialize(ethPrice,floor,reserveStart, ceiling, crowdSaleAllocation);
            let balance = await erc20Contract.balanceOf(crowdsaleContract.address);
            assert.equal(balance.toNumber(), crowdSaleAllocation ,"Balnce should be equal to allocated amount")
            let stage = await crowdsaleContract.currentStage();
            assert.equal(stage, 1, "Stage should be crowdsale");
        })

        it('Should deploy Airdrop contract and aidrop stage should be 0', async function () {
            airdropContract = await Airdrop.new(erc20Contract.address);
            let stage = await airdropContract.currentStage();
            assert.equal(stage.toNumber(), airdropDeployed, "Stage should be airdrop deployed")
        })

        it('FundKeeper, Manager and Recoverer  should be owner', async function () {
            let fundkeeper = await erc20Contract.isFundkeeper(owner);
            assert.equal(fundkeeper, true, "Fundkeeper is the owner")
            let manager = await airdropContract.isManager(owner);
            assert.equal(manager, true, "Manager is the owner")
            let recoverer = await airdropContract.isRecoverer(owner);
            assert.equal(recoverer, true, "Recoverer is the owner")
        })

        it('Negative tests FundKeeper, Manager and Recoverer ', async function () {
            let fundkeeper = await erc20Contract.isFundkeeper(accounts[1]);
            assert.equal(fundkeeper, false, "Fundkeeper is not a diferent account from owner")
            let manager = await airdropContract.isManager(accounts[1]);
            assert.equal(manager, false, "Manager is not a diferent account from owner")
            let recoverer = await airdropContract.isRecoverer(accounts[1]);
            assert.equal(recoverer, false, "Recoverer  is not a diferent account from owner")
        })

        it('Should reject when other account tries to approve funds', async function () {
            await erc20Contract.approve(airdropContract.address, airdropTokens, { from: accounts[1] }).should.be.rejected;
        })

        it('Fund keeper Should approve to transfer tokens to airdrop contract ', async function () {
            airdropTokens = await erc20Contract.balanceOf(owner);
            airdropTokens = airdropTokens.toNumber();
            airdropTokens = airdropTokens / 2;
            await erc20Contract.approve(airdropContract.address, airdropTokens)
            let allowedTokens = await erc20Contract.allowance(owner, airdropContract.address)
            assert.equal(allowedTokens.toNumber(), airdropTokens, "Approved tokens should be equal allowance");
        })

        it('Before initalize airdrop contract balance should be zero', async function () {
            let airdropContractBlnce = await erc20Contract.balanceOf(airdropContract.address);
            assert.equal(airdropContractBlnce.toNumber(), 0, "airdropContractBlnce should be 0 ")
        })

        it('initalize should fail if not manager', async function () {
            await airdropContract.initilize(airdropTokens, { from: accounts[1] }).should.be.rejected;
        })

        it('Should Initialize airdrop to allocate tokens to the contract ', async function () {
            await airdropContract.initilize(airdropTokens);
            let ownerBalance = await erc20Contract.balanceOf(owner);
            assert.equal(ownerBalance.toNumber(), airdropTokens, "Fundkeeper should have the remaining balance")
            let airdropContractBlnce = await erc20Contract.balanceOf(airdropContract.address);
            assert.equal(airdropContractBlnce.toNumber(), airdropTokens, "airdropContractBlnce should be equal to the allocated airdrop tokens ")
        })  

        it('TotalSupply, token allocation and distributedTokens should match the airdrop tokens', async function() {
            
            let contractAllocation = await airdropContract.getAllocation();
            assert.equal(contractAllocation.toNumber(), airdropTokens,"getAllocation should return airdrop tokens")
            
            totalSupply = await airdropContract.totalSupply();
            assert.equal(totalSupply.toNumber(), airdropTokens,"totalSupply should return airdrop tokens")

            distributedTokens = await airdropContract.getDistribution();
            assert.equal(distributedTokens.toNumber(),0,"distributedTokens should be equal to 0") 
        })

        it('Stage should be airdrop ', async function () {
            let stage = await airdropContract.currentStage();
            assert.equal(stage.toNumber(), airdrop, "Stage should be airdrop deployed")
        })

        describe('Airdrop fund allocation {by Manager}', async function () {

            /**
             * Airdrop funds by user
             */
            const allocation1 = new BigNumber(45000 * WEI)
            const allocation2 = new BigNumber(35000 * WEI)
            const allocation3 = new BigNumber(30000 * WEI)
            const allocation4 = new BigNumber(101 * WEI)
            const allocation5 = new BigNumber(99 * WEI)

            it('Manager should be able to allocate tokens to a user', async function () {
                await airdropContract.addBalance([accounts[10], accounts[11], accounts[12], accounts[13], accounts[14]], [allocation1.toString(), allocation2.toString(), allocation3.toString(), allocation4.toString(), allocation5.toString()])
            })

            it('Should reject a null address', async function() {
                await airdropContract.addBalance([nullAddress],[allocation1]).should.be.rejected;
            })

            it('TotalSupply and distributedTokens should match the allocated tokens', async function() {
                airdropTokens = new BigNumber(airdropTokens)
                let caldistributedTokens = allocation1.plus(allocation2).plus(allocation3).plus(allocation4).plus(allocation5)
                let calctotalSupply = airdropTokens.minus(caldistributedTokens);
         
                totalSupply = await airdropContract.totalSupply();
                assert.equal(totalSupply.toNumber(), calctotalSupply,"totalSupply should return airdrop tokens")
    
                distributedTokens = await airdropContract.getDistribution();
                assert.equal(distributedTokens.toNumber(),caldistributedTokens.toNumber(),"distributedTokens should be equal to caldistributedTokens") 
            })

            it('Should return the claimTokens and allocatedTokens of an account', async function() {
                let allocated1 = await airdropContract.allocationOf(accounts[14])
                assert.equal(allocated1.toNumber(), allocation5.toNumber(),"allocated balance should match")

                let airdropBalance1 = await airdropContract.airdropBalanceOf(accounts[14])
                assert.equal(airdropBalance1.toNumber(), allocation5.toNumber(),"airdropBalance should match")
            })

            it('Claim should be rejected for 0 balance', async function() {
                await airdropContract.claim({from : accounts[3]}).should.be.rejected;
            })

            it('Claim should be rejected before 1 day interval and before crowdsale address is set', async function() {
                await airdropContract.claim({from : accounts[14]}).should.be.rejected;
            })

            it('Should set crowdsale address', async function() {
                await airdropContract.setCrowdsale(crowdsaleContract.address)
            })

            it('Should be able to claim all the tokens when balance less than 100', async function() {
                await manipulateBlocks();
                await airdropContract.claim({from : accounts[14]})
                
                let balance = await erc20Contract.balanceOf(accounts[14]);
                assert.equal(balance.toNumber(), 99 * WEI, "Should be able to claim 99 tokens")
            })

            describe('Should be able to claim daily ', function() {
                it('Claim 1% of allocation on first day ', async function() {
                    await airdropContract.claim({from: accounts[13]})
                })

                it('Balance should be equal to 1% of allocated tokens',async function() {
                    let balance = await erc20Contract.balanceOf(accounts[13]);
                    assert.equal(balance.toNumber(), 100 * WEI, "total balance should be equal to 1% allocated tokens");
                })
                
                it('Remaining balance should be total tokens minus 1% of allocated tokens ',async function() {
                    let airdropBalance = await airdropContract.airdropBalanceOf(accounts[13])
                    assert.equal(airdropBalance.toNumber(), 1 * WEI, "remaining balance should be 1 WEI");
                })

                it('Should be able to claim the remaining tokens after 1 day interval', async function() {
                    await manipulateBlocks();
                    await airdropContract.claim({from: accounts[13]})
                })

                it('Balance should be equal to 1% of allocated tokens',async function() {
                    let balance = await erc20Contract.balanceOf(accounts[13]);
                    assert.equal(balance.toNumber(), 101 * WEI, "total balance should be equal to the allocated tokens");
                })
                
                it('Remaining balance should be total tokens minus 1% of allocated tokens ',async function() {
                    let airdropBalance = await airdropContract.airdropBalanceOf(accounts[13])
                    assert.equal(airdropBalance.toNumber(), 0 , "remaining balance should be 0");
                })
            
            })

            describe('Should accumulate and claim tokens', async function() {
                let claimBlock;
                let currentBlock;
                let accumulatedTokens;
                let remainingTokens;

                it('Airdrop balance should be equal to the allocated tokens', async function() {
                    let airdropBalance = await airdropContract.airdropBalanceOf(accounts[12])
                    assert.equal(airdropBalance.toNumber(), allocation3 , "aidrop balance should be equal to the allocated balance");
                })

                it('Should return the claim block of an address ', async function() {
                    await manipulateBlocks();
                    claimBlock = await airdropContract.claimBlock(accounts[12])
                    currentBlock = await web3.eth.getBlockNumber()
                })

                it('Should be able to claim the accumulated tokens', async function() {
                    let days = (currentBlock - claimBlock.toNumber())/claimPeriod; //calculating number of days to calculate the accumulated tokens 
                    accumulatedTokens = allocation3 * onePerc * Number(days.toFixed(0))
                    await airdropContract.claim({from: accounts[12]})
                })

                it('Balance should be equal to the accumulated tokens', async function() {
                    let balance = await erc20Contract.balanceOf(accounts[12]);
                    assert.equal(balance.toNumber(), accumulatedTokens , "total balance should be equal to the allocated tokens");
                })
                
                it('Remaining balance should be equal to calculated tokens ',async function() {
                    let airdropBalance = await airdropContract.airdropBalanceOf(accounts[12])
                    let calBal = allocation3.minus(accumulatedTokens) 
                    assert.equal(airdropBalance.toNumber(), calBal , "remaining balance should be equal to calcBal");
                })
            })

            describe('Claim and transfer tokens to another account', function() {
                it('Should claim tokens', async function() {
                    await airdropContract.claim({from:accounts[11]});
                })

                it('Should be able to transfer tokens', async function() {
                    let balance1 = await erc20Contract.balanceOf(accounts[12]);
                    await erc20Contract.transfer(accounts[4], balance1.toNumber());
                    let balance = await erc20Contract.balanceOf(accounts[12]);
                    assert.equal(balance.toNumber(),balance1.toNumber(),"Transferred balance should be equal")
                })
                
            })

            describe('Decrease token allocation and airdrop', async function() {
    
                it('Should change the manager and allocate tokens', async function() {
                    await airdropContract.addManager(accounts[1]);
                    let manager = await airdropContract.isManager(accounts[1]);
                    assert.equal(manager, true, "Manager is the owner")
                })
                
                it('Should be able to reduce tokens from particular address ', async function() {
                    let airdropBalance = await airdropContract.airdropBalanceOf(accounts[10])
                    assert.equal(airdropBalance.toNumber(), allocation1.toNumber() , "Balance should be equal to allocation1");
    
                    allocation = allocation3.toNumber();
                    await airdropContract.subBalance([accounts[10]],[allocation],{from:accounts[1]})
                    
                    let calBal = allocation1.minus(allocation)
                    airdropBalance = await airdropContract.airdropBalanceOf(accounts[10])
                    assert.equal(airdropBalance.toNumber(), calBal.toNumber() , "Balance should be equal to 35000 wei");
                })
    
                // //Vulnerability
                it('Should reject when owner tries to recover tokens before airdrop ends',async function() {
                    await airdropContract.recoverTokens(erc20Contract.address).should.be.rejected;
                })
                
                it('Should be able to end airdrop',async function() {
                    await airdropContract.airdropEnd({from: accounts[1]})
                    let stage = await airdropContract.currentStage();
                    assert.equal(stage.toNumber(), airdropEnded , "Stage should be 2 after airdrop end")
                })

                it('Should be able to claim after airdrop ends', async function() {
                    await airdropContract.claim({from:accounts[10]}).should.be.rejected;
                })
    
                it('Should be able to recover all tokens ', async function() {
                    await airdropContract.recoverTokens(erc20Contract.address);
                    let contractBal = await erc20Contract.balanceOf(airdropContract.address);
                    assert.equal(contractBal.toNumber(), 0 ," Contract balance should be equal to 0")
                })
            })
            
        })

    })

    function manipulateBlocks() {
        return new Promise( async resolve => {
         for(i =0; i<= claimPeriod; i++) {
             await airdropContract.claim({from : accounts[3]}).should.be.rejected;
         }
         resolve()
        })
     }
})





