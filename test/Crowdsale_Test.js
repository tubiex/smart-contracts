const TBNERC20 = artifacts.require('./TBNERC20');
const Crowdsale = artifacts.require("./TBNCrowdsale.sol");
const BigNumber = require('bignumber.js');
const assert = require("chai").assert;
require('chai')
    .use(require('chai-as-promised'))
    .should();

/* Web 3 Objects */
const Web3 = require('web3');
const web3 = new Web3('http://localhost:7545');


contract('Crowdsale contract test', function (accounts) {
    /**
    * Global Variables
    */
    let erc20Contract;
    let crowdsaleContract;
    let hiddenCapHash;

    /**
    * Global Constants
    */
    const WEI = 1e18;
    const TOTAL_SUPPLY = 380000000 * WEI;
    
    /**
     * Crowdsale Constants
     */
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
    const claimPeriod = 30;

    
    /**
     * Normal flow 
     */
    describe('Deployment and initialisation', function() {
        before(' Deploy erc20 contract', async function () {
            erc20Contract = await TBNERC20.new(TOTAL_SUPPLY, "Tubiex Network Token", "TBN", 18);
            hiddenCapHash = web3.utils.soliditySha3(hiddenCap,secretNumber)
            crowdsaleContract = await Crowdsale.new(erc20Contract.address, intervals, guaranteedIntervals, hiddenCapHash)
        })

        it('Should approve for crowdsale contract', async function() {
            await erc20Contract.approve(crowdsaleContract.address, crowdSaleAllocation);
            let allowance = await erc20Contract.allowance(accounts[0], crowdsaleContract.address);
            assert.equal(allowance.toNumber(), crowdSaleAllocation, "Allowance should be equal to allocation")
        })

        it('Should reject if ETH basis price is less than reserve ceiling ', async function() {
            const invalidEthPrice = 1;
            await crowdsaleContract.initialize(invalidEthPrice,floor,reserveStart,ceiling, crowdSaleAllocation).should.be.rejected;
        })

        it('Should reject if reserve floor is not greater than 0', async function() {
            const invalidfloor = 0;
            await crowdsaleContract.initialize(ethPrice,invalidfloor,reserveStart,ceiling, crowdSaleAllocation).should.be.rejected;
        })

        it('Should reject if reserve ceiling < _numberOfIntervals + reserve floor', async function() {
            const invalidceiling = 125;
            await crowdsaleContract.initialize(ethPrice,floor,invalidceiling, crowdSaleAllocation).should.be.rejected;
        })

        it('Should reject if crowdsale allocation is less than 0"', async function() {
            const invalidcrowdSaleAllocation = 0;
            await crowdsaleContract.initialize(ethPrice,floor,reserveStart,ceiling, invalidcrowdSaleAllocation).should.be.rejected;
        })

        it(' Should initialize crowdsale contract', async function() {
            await crowdsaleContract.initialize(ethPrice,floor,reserveStart, ceiling, crowdSaleAllocation);
            let balance = await erc20Contract.balanceOf(crowdsaleContract.address);
            assert.equal(balance.toNumber(), crowdSaleAllocation ,"Balnce should be equal to allocated amount")
            let stage = await crowdsaleContract.currentStage();
            assert.equal(stage, 1, "Stage should be crowdsale");
        })

        it('Should add to whitelist', async function() {
            await crowdsaleContract.addToWhitelist([accounts[1],accounts[2],accounts[3]],{from: accounts[1]}).should.be.rejected;
            await crowdsaleContract.addToWhitelist([accounts[1],accounts[2],accounts[3],accounts[4],accounts[5],accounts[6],accounts[7],accounts[8],accounts[9]]);
            let isWhitelist = await crowdsaleContract.whitelist(accounts[1])
            assert.equal(isWhitelist, true, "It should return true")
        })
    })

    describe('Participate, claim, rebase, adjust reserve reveal cap and recoverTokens', function(){
        crowdSaleAlloc = new BigNumber(crowdSaleAllocation)
        let tokensPerInterval = crowdSaleAlloc.dividedBy(intervals);
        let blockNumber;
        let interval;
        let reservePrice;
        let reserveAmount;
        let bid_total;

        /**
         * Scenario - 1: One person participates with amount equal to ethReserveAmount
         * So he can claim all the tokens allocated for that day
         * 
         * Tests : Normal participate and claim is checked
         */
        describe('Interval: 0 participate and claim without limit', async function() {
            let firstBid = web3.utils.toWei(web3.utils.toBN(10),"ether");
            let first_bid;

            it('Should participate in crowdsale', async function() {
                await crowdsaleContract.participate(0, {from: accounts[1], value:firstBid });
                blockNumber = await web3.eth.getBlockNumber()                
                interval = await crowdsaleContract.getInterval(blockNumber);
                assert.equal(interval.toNumber(), 0, "Interval should be 0")
            })

            it('Should verify reservePrice and reserveAmount ', async function() {
                reservePrice = 10000000000000000;
                reserveAmount = 10000000000000000000;
                let intervalValue = await crowdsaleContract.intervals(0);
                assert.equal(intervalValue[0].toNumber(),reservePrice, "Reserve Price should be equal to calculated value" )
                assert.equal(intervalValue[1].toNumber(),reserveAmount, "Reserve Amount should be equal calculated value" )
            })

            it(' Should return contribution per interval', async function() {
                first_bid = await crowdsaleContract.intervalTotals(0)
                assert.equal(first_bid.toNumber(), firstBid, "intervalTotals Should be equal to first bid")

                first_bid = await crowdsaleContract.participationAmount(0,accounts[1])
                assert.equal(first_bid.toNumber(), firstBid, "participationAmount Should be equal to first bid")
            })

            it('Should reject claim on the same interval', async function() {
                await crowdsaleContract.claim(0,{from: accounts[1]}).should.be.rejected
                let balance = await erc20Contract.balanceOf(accounts[1])
                assert.equal(balance.toNumber(), 0 , "Balnce should be 0")
            })

            it('Should create interval blocks', async function() {
                await manipulateBlocks(1);
            })

        })

        /***
         * Tests : Normal participate and claim is checked
         * 
         * Scenario 2 : One person participates with limit success equal to ethReserveAmount
         * Rebase the ethPrice so that in next interval ethReserveAmount increases
         * 
         */
        describe('Interval-1 participate and claim with limit', async function() {
            let secondBid = web3.utils.toWei(web3.utils.toBN(10),"ether");
            let limit = 100000000000000000000;

            it('Should change interval', async function() {
                blockNumber = await web3.eth.getBlockNumber()                
                interval = await crowdsaleContract.getInterval(blockNumber);
                assert.equal(interval.toNumber(), 1, "Interval should be 1")
            })

            it('Should be able to claim tokens for 0th interval', async function() {   
                await crowdsaleContract.claim(0,{from: accounts[1]})
                
                let balance = await erc20Contract.balanceOf(accounts[1])
                assert.equal(balance.toNumber(), tokensPerInterval.toNumber(),"Balance should be equal to tokens per interval")

                let isClaimed = await crowdsaleContract.claimed(0,accounts[1]);
                assert.equal(isClaimed,true,"Should return true for already claimed accounts")  
            })

            it('ReservePrice and reserveAmount should be the same as interval 0', async function() {
                let intervalValue = await crowdsaleContract.intervals(1);
                assert.equal(intervalValue[0].toNumber(),reservePrice, "Reserve Price should be equal to calculated value" )
                assert.equal(intervalValue[1].toNumber(),reserveAmount, "Reserve Amount should be equal calculated value" )
            })

            it('Should participate in crowdsale', async function() {
                await crowdsaleContract.participate(limit, {from: accounts[2], value:secondBid });
            })

            it('Should create interval blocks', async function() {
                await manipulateBlocks(1);
            })
            
            it('Should rebase the ethPrice to 10 usd', async function() {
                await crowdsaleContract.setRebase(newEthPrice);
            })
            
        })

        /**
         * * Tests : Normal participate and claim is checked
         * 
         * Scenario 3: 
         * Two people contributing equal than ethReserve with limit success
         * So both can claim 50% of the tokens allocated for that day
         * 
         * Negative case 1: One person participates with limit(which reverts) equal that ethReserveAmount
         * 
         */
        describe('Interval-2 crowdsale tests participate and claim for multiple accounts', function() {
            let firstBid = web3.utils.toWei(web3.utils.toBN(10),"ether");
            let secondBid = web3.utils.toWei(web3.utils.toBN(5),"ether");
            
            let limit = 1000000000000000000000;

            it('Should change interval', async function() {
                blockNumber = await web3.eth.getBlockNumber()                
                interval = await crowdsaleContract.getInterval(blockNumber);
                assert.equal(interval.toNumber(), 2, "Interval should be 2")
            })
            
            it('Should be able to claim tokens for 1st Interval', async function() {   
                await crowdsaleContract.claim(1,{from: accounts[2]})
                
                let balance = await erc20Contract.balanceOf(accounts[2])
                assert.equal(balance.toNumber(), tokensPerInterval.toNumber(),"Balance should be equal to tokens per interval")

                let isClaimed = await crowdsaleContract.claimed(1,accounts[2]);
                assert.equal(isClaimed,true,"Should return true for already claimed accounts")  
            })

            //Negative case 1:
            it('Should reject participate for limit more than TBNPerEth', async function() {
                await crowdsaleContract.participate(limit, {from: accounts[1], value:firstBid }).should.be.rejected;
            })

            it('ReservePrice and reserveAmount should be unchanged', async function() {
                let intervalValue = await crowdsaleContract.intervals(2);
                
                assert.equal(intervalValue[0].toNumber(),reservePrice, "Reserve Price should be equal to calculated value" )
                assert.equal(intervalValue[1].toNumber(),reserveAmount, "Reserve Amount should be equal calculated value" )
            })

            it('Should participate from 2 accounts', async function() {
                await crowdsaleContract.participate(0, {from: accounts[3], value:secondBid });
                await crowdsaleContract.participate(0, {from: accounts[4], value:secondBid });
            })

            it(' Should return contribution per interval', async function() {
                bid_total = await crowdsaleContract.intervalTotals(2)
                assert.equal(bid_total.toNumber(), firstBid, "intervalTotals Should be equal to 2 times secondBid")

                bid1 = await crowdsaleContract.participationAmount(2,accounts[3])
                assert.equal(bid1.toNumber(), secondBid, "participationAmount Should be equal to secondBid value")

                bid2 = await crowdsaleContract.participationAmount(2,accounts[4])
                assert.equal(bid2.toNumber(), secondBid, "participationAmount Should be equal to secondBid value")
            })

            it('Should create interval blocks', async function() {
                await manipulateBlocks(1);
            })
        })

        /**
         * Tests : Normal participate and claim for different contribution is checked
         * 
         * Scenario 3: 4 person participate for different proportion 
         *  total value equal to resveAmount: acc5 to acc8 : 1,2,2,5
         * 
         * Negative case 2: One person participates without limit for old ethReserve i.e 10Eth (which should revert due to rebase)
         * 
         * On claim : each person should get thier contribution of tokens 100, 200, 200, 500 
         *
         */
        describe('Interval-3 crowdsale tests participate and claim for different contribution%', function() {
            let interval1Token = tokensPerInterval.dividedBy(2);
            let rebaseLimit = 100000000000000000000;

            let oldEthReserve = web3.utils.toWei(web3.utils.toBN(10),"ether");
            let totalBid = web3.utils.toWei(web3.utils.toBN(100),"ether");
            let bid1 = web3.utils.toWei(web3.utils.toBN(10),"ether");
            let bid2 = web3.utils.toWei(web3.utils.toBN(20),"ether");
            let bid3 = web3.utils.toWei(web3.utils.toBN(20),"ether");
            let bid4 = web3.utils.toWei(web3.utils.toBN(50),"ether");

            it('Should change interval', async function() {
                blockNumber = await web3.eth.getBlockNumber()                
                interval = await crowdsaleContract.getInterval(blockNumber);
                assert.equal(interval.toNumber(), 3, "Interval should be 3")
            })

            it('Should be able to claim tokens in second Interval', async function() {
                await crowdsaleContract.claim(2,{from:accounts[3]})
                await crowdsaleContract.claim(2,{from:accounts[4]})
            })

            it('Token Balance should be 50% of the total tokens', async function() {
                let balance = await erc20Contract.balanceOf(accounts[3])                                    
                assert.equal(balance.toNumber(), interval1Token.toNumber(),"Balance should be equal to 50% of tokens per interval")

                balance = await erc20Contract.balanceOf(accounts[4])                                    
                assert.equal(balance.toNumber(), interval1Token.toNumber(),"Balance should be equal to 50% of tokens per interval")
            })

            //Rebase reflect in next interval
            it('ReservePrice and reserveAmount should greater than oldReserve due to rebase', async function() {
                let intervalValue = await crowdsaleContract.intervals(3);
                assert.isAbove(intervalValue[0].toNumber(),reservePrice, "Reserve Price should be greater than calculated value" )
                assert.isAbove(intervalValue[1].toNumber(),reserveAmount, "Reserve Amount should be greater than  calculated value" )
            })

            //Negative case 2:
            it('Should reject participate for limit more than TBNPerEth', async function() {
                await crowdsaleContract.participate(rebaseLimit, {from: accounts[1], value:oldEthReserve }).should.be.rejected;
            })

            it('Should participate from 4 accounts', async function() {
                await crowdsaleContract.participate(0, {from: accounts[5], value:bid1 });
                await crowdsaleContract.participate(0, {from: accounts[6], value:bid2 });
                await crowdsaleContract.participate(0, {from: accounts[7], value:bid3 });
                await crowdsaleContract.participate(0, {from: accounts[8], value:bid4 });
            })

            it(' Should return total contribution per interval', async function() {
                bid_total = await crowdsaleContract.intervalTotals(3)
                assert.equal(bid_total.toNumber(), totalBid, "intervalTotals Should be equal sum of all fourbids")
            })


            it('Should rebase the ethPrice to 100 usd', async function() {
                await crowdsaleContract.setRebase(ethPrice);
            })

            it('Should create interval blocks', async function() {
                await manipulateBlocks(1);
            })


        })

        /***
         * Testing adjustReserve functionality 
         * 
         * Scenario 4: 1 person participate for 7 ether (i.e 30% less than lastReserveAmount)
         * ReserveAmount should reduce by 0.5 ether 
         * On Claim he can claim only 70% of the totalTokens
         * 
         */
        describe('Interval-4 : Test to reduce the adjustReserve under 30%', function() {
            let bid1 = web3.utils.toWei(web3.utils.toBN(7),"ether");

            it('Should change interval', async function() {
                blockNumber = await web3.eth.getBlockNumber()                
                interval = await crowdsaleContract.getInterval(blockNumber);
                assert.equal(interval.toNumber(), 4, "Interval should be 4")
            })

            it('Should be able to claim in next interval', async function() {
                await crowdsaleContract.claim(3,{from:accounts[5]})
                await crowdsaleContract.claim(3,{from:accounts[6]})
                await crowdsaleContract.claim(3,{from:accounts[7]})
                await crowdsaleContract.claim(3,{from:accounts[8]})
            })

            it('Token Balance should be equal to thier proportion of the total tokens', async function() {
                let calcBid = 100 * WEI;
                let balance = await erc20Contract.balanceOf(accounts[5])                                    
                assert.equal(balance.toNumber(), calcBid ,"Balance should be equal to 10% of tokens per interval")

                calcBid = 200 * WEI;
                balance = await erc20Contract.balanceOf(accounts[6])                                    
                assert.equal(balance.toNumber(), calcBid ,"Balance should be equal to 20% of tokens per interval")

                calcBid = 200 * WEI;
                balance = await erc20Contract.balanceOf(accounts[7])                                    
                assert.equal(balance.toNumber(), calcBid ,"Balance should be equal to 20% of tokens per interval")

                calcBid = 500 * WEI;
                balance = await erc20Contract.balanceOf(accounts[8])                                    
                assert.equal(balance.toNumber(), calcBid ,"Balance should be equal to 50% of tokens per interval")
            })

            // Rebase reflect in next interval
            it('ReservePrice and reserveAmount should greater than oldReserve due to rebase', async function() {
                let intervalValue = await crowdsaleContract.intervals(4);
                assert.equal(intervalValue[0].toNumber(),reservePrice, "Reserve Price should be equal to calculated value" )
                assert.equal(intervalValue[1].toNumber(),reserveAmount, "Reserve Amount should be equal calculated value" )
            })

            //Should particiapte for 30% less than ethReserve
            it('Should participate for less eth than ethReserve amount', async function() {
                await crowdsaleContract.participate(0, {from: accounts[9], value:bid1 });
            })

            it(' Should return total contribution per interval', async function() {
                bid_total = await crowdsaleContract.intervalTotals(4)
                assert.equal(bid_total.toNumber(), bid1 , "intervalTotals Should be equal sum of all fourbids")
            })

            
            it('Should create interval blocks', async function() {
                await manipulateBlocks(1);
            })
        })

        /***
         * Testing adjustReserve functionality
         * 
         * Scenario 5: 1 person participate for 10 ether (i.e 30% more than lastReserveAmount)
         * ReserveAmount should increase by 0.5 ether 
         * On Claim he can claim all  totalTokens for the day
         * 
         */
        describe('Interval-5 : Test to increase adjustReserve by 30%',function() {
            let bid1 = web3.utils.toWei(web3.utils.toBN(10),"ether");

            it('Should change interval', async function() {
                blockNumber = await web3.eth.getBlockNumber()         
                interval = await crowdsaleContract.getInterval(blockNumber);
                assert.equal(interval.toNumber(), 5, "Interval should be 5")
            })

            it('Should be able to claim in next interval', async function() {
                await crowdsaleContract.claim(4 ,{from:accounts[9]})
            })

            it('Balance should be equal to 70% of the total tokens ', async function() {
                calBal = 700 * WEI;
                let balance = await erc20Contract.balanceOf(accounts[9]);
                assert.equal(balance.toNumber(),calBal, "Balance should be equal 70% of total tokens" )
                
            })

            it('ReservePrice and reserveAmount should be less than the previous interval', async function() {
                let intervalValue = await crowdsaleContract.intervals(6);
                
                assert.isBelow(intervalValue[0].toNumber(),reservePrice, "Reserve Price should be  below lastEthReservePrice" )
                assert.isBelow(intervalValue[1].toNumber(),reserveAmount, "Reserve Amount should be below lastEthReserve" )

                reservePrice = intervalValue[0];
                reserveAmount = intervalValue[1];
            })

            it('Should whitelist next set of accounts', async function() {
                await crowdsaleContract.addToWhitelist([accounts[11],accounts[12],accounts[13],accounts[14],accounts[10]]);
            })

            it('Should participate for 30% more than the ethReserveAmount', async function() {
                await crowdsaleContract.participate(0, {from: accounts[10], value:bid1 });
            })
            
            it('Should create interval blocks', async function() {
                await manipulateBlocks(1);
            })
        })

        /***
         * Testing adjustReserve functionality 
         * 
         * Scenario 6: 1 person participate for 3 ether (i.e 70% less than lastReserveAmount)
         */

        describe('Interval-6  & 7: Test to reduce the adjustReserve by 70%', async function() {
            let bid1 = web3.utils.toWei(web3.utils.toBN(3),"ether");

            it('Should change interval', async function() {
                blockNumber = await web3.eth.getBlockNumber() 
                               
                let interval = await crowdsaleContract.getInterval(blockNumber);
                assert.equal(interval.toNumber(), 7, "Interval should be 6")
            })

            it('Should be able to claim in next interval', async function() {
                await crowdsaleContract.claim(6 ,{from:accounts[10]})
            })

            it('Balance should be equal to the total tokens ', async function() {
                let balance = await erc20Contract.balanceOf(accounts[10]);
                assert.equal(balance.toNumber(),tokensPerInterval, "Balance should be equal to total tokens" )
                
            })

            it('ReservePrice and reserveAmount should be less than the previous interval', async function() {
                let intervalValue = await crowdsaleContract.intervals(7);
                
                assert.isAbove(intervalValue[0].toNumber(),reservePrice.toNumber(), "Reserve Price should be  above lastEthReservePrice" )
                assert.isAbove(intervalValue[1].toNumber(),reserveAmount.toNumber(), "Reserve Amount should be above lastEthReserve" )

                reservePrice = intervalValue[0];
                reserveAmount = intervalValue[1];
            })

            it('Should participate for 3 eth', async function() {
                await crowdsaleContract.participate(0, {from: accounts[11], value:bid1 });
            })

            it('Should create interval blocks', async function() {
                await manipulateBlocks(1);
            })
        })

        /***
         * Testing adjustReserve functionality 
         * 
         * Scenario 8: 1 person participate for 10 ether (i.e 70% more than lastReserveAmount)
         */
        describe('Interval-8 : Test to increase the adjustReserve by 70%', function() {
            let bid1 = web3.utils.toWei(web3.utils.toBN(10),"ether");

            it('Should change interval', async function() {
                blockNumber = await web3.eth.getBlockNumber() 
                               
                let interval = await crowdsaleContract.getInterval(blockNumber);
                assert.equal(interval.toNumber(), 8, "Interval should be 8")
            })

            it('Should be able to claim in next interval', async function() {
                await crowdsaleContract.claim(7 ,{from:accounts[11]})
            })

            it('Balance should be equal to the total tokens ', async function() {
                let calTokens = 300 * WEI;
                let balance = await erc20Contract.balanceOf(accounts[11]);
                assert.isAtLeast(balance.toNumber(),calTokens, "Balance should be atleast equal to 30% of total tokens" )
                
            })

            it('ReservePrice and reserveAmount should be less than the previous interval', async function() {
                let intervalValue = await crowdsaleContract.intervals(8);
                
                assert.isBelow(intervalValue[0].toNumber(),reservePrice.toNumber(), "Reserve Price should be  below lastEthReservePrice" )
                assert.isBelow(intervalValue[1].toNumber(),reserveAmount.toNumber(), "Reserve Amount should be below lastEthReserve" )

                reservePrice = intervalValue[0];
                reserveAmount = intervalValue[1];                
            })

            it('Should participate for 10 eth', async function() {
                await crowdsaleContract.participate(0, {from: accounts[12], value:bid1 });
            })

            it('Should create interval blocks', async function() {
                await manipulateBlocks(1);
            })
        })
        /***
         * Scenario participate equal to ethReserve and not claim
         * 
         * This is to check claimALl feature later 
         */
        describe('Interval-9 : Test to increase adjustReserve by 70%',function() {
            let bid1 = web3.utils.toWei(web3.utils.toBN(10),"ether");

            it('Should change interval', async function() {
                blockNumber = await web3.eth.getBlockNumber()         
                interval = await crowdsaleContract.getInterval(blockNumber);
                assert.equal(interval.toNumber(), 9, "Interval should be 9")
            })

            it('Should be able to claim in next interval', async function() {
                await crowdsaleContract.claim(8 ,{from:accounts[12]})
            })

            it('Balance should be equal to 70% of the total tokens ', async function() {
                calBal = 1000 * WEI;
                let balance = await erc20Contract.balanceOf(accounts[12]);
                assert.equal(balance.toNumber(),calBal, "Balance should be equal 70% of total tokens" )
            })

            it('ReservePrice and reserveAmount should be more than the previous interval', async function() {
                let intervalValue = await crowdsaleContract.intervals(9);
                
                assert.isAbove(intervalValue[0].toNumber(),reservePrice.toNumber(), "Reserve Price should be  above lastEthReserve" )
                assert.isAbove(intervalValue[1].toNumber(),reserveAmount.toNumber(), "Reserve Amount should be above lastEthReserve" )

                reservePrice = intervalValue[0];
                reserveAmount = intervalValue[1];
            })

            it('Should whitelist next set of accounts', async function() {
                await crowdsaleContract.addToWhitelist([accounts[15],accounts[16],accounts[17],accounts[18],accounts[19]]);
            })

            it('Should participate for ethReserveAmount', async function() {
                await crowdsaleContract.participate(0, {from: accounts[13], value:bid1 });
                await crowdsaleContract.participate(0, {from: accounts[14], value:bid1 });
            })
            
            it('Should create interval blocks', async function() {
                let endBlock = await crowdsaleContract.endBlock();
                endBlock = endBlock.toNumber();
                
                block = await web3.eth.getBlockNumber();
                left = endBlock - block;

                for(i = 1; i< left; i++) {
                    await crowdsaleContract.addToWhitelist([accounts[1],accounts[2],accounts[3]],{from: accounts[1]}).should.be.rejected;
                }
                
            })
        })
        
        let contractBalance; 

        /***
         * Secenario 10 : To test recover tokens , addDistribution and claimALl after end of the intervals
         */
        describe('Interval 10: Last interval just participate', function() {
            let bid1 = web3.utils.toWei(web3.utils.toBN(50),"ether");

            it('Should change interval', async function() {
                let blockNumber = await web3.eth.getBlockNumber()
                    
                interval = await crowdsaleContract.getInterval(blockNumber);
                assert.equal(interval.toNumber(), 9 , "Interval should be 9")
            })

            it('Should participate more than ethReserve', async function() {
                await crowdsaleContract.participate(0, {from: accounts[14], value:bid1 });
            })

            it('Should create interval blocks', async function() {
                await manipulateBlocks(1);
            })
        })

        /***
         * Senario : After the end of the intervals trying to participate , claimAll and receover
         * 
         */
        describe('Sale ended: Test recover and collect funds', function() {
            let acc13Bid = web3.utils.toWei(web3.utils.toBN(10),"ether");
            let acc14Bid = web3.utils.toWei(web3.utils.toBN(60),"ether");

            it('Sale ended should not be able to participate',async function() {
                await crowdsaleContract.participate(0, {from: accounts[15], value:acc13Bid }).should.be.rejected;
            })

            it('Check the participation amount ', async function() {
                acc13 = await crowdsaleContract.participationAmount(9,accounts[13])
                assert.equal(acc13.toNumber(),acc13Bid,"calculated value should be equal")

                acc14 = await crowdsaleContract.participationAmount(9,accounts[14])
                acc14 = new BigNumber(acc14)
                value = await crowdsaleContract.participationAmount(10,accounts[14])
                acc14 = acc14.plus(value.toNumber())

                assert.equal(acc14.toNumber(),acc14Bid,"calculated value should be equal")
            })

            it('Both the accounts claim value should be false', async function() {
                let isClaimed = await crowdsaleContract.claimed(9,accounts[13]);
                assert.equal(isClaimed,false,"Should return be false")  
                isClaimed = await crowdsaleContract.claimed(9,accounts[14]);
                assert.equal(isClaimed,false,"Should return be false")  
                isClaimed = await crowdsaleContract.claimed(10,accounts[14]);
                assert.equal(isClaimed,false,"Should return be false")  
            })

            it('Should claimAll for both the accounts', async function() {
                await crowdsaleContract.claimAll({from:accounts[13]})
                await crowdsaleContract.claimAll({from:accounts[14]})
            })  

            it('Should change the state to crowdsale ended', async function() {
                let stage = await crowdsaleContract.currentStage()
                assert.equal(stage.toNumber(),2,"stage should be ended")  
            })

            it('Should change the claim Status', async function() {
                let isClaimed = await crowdsaleContract.claimed(9,accounts[13]);
                assert.equal(isClaimed,true,"Should return be true")  
                isClaimed = await crowdsaleContract.claimed(9,accounts[14]);
                assert.equal(isClaimed,true,"Should return be true")  
                isClaimed = await crowdsaleContract.claimed(10,accounts[14]);
                assert.equal(isClaimed,true,"Should return be true")  
            })

            it('Should check the balance of accounts after claimAll', async function() {
                let calClaim = 500 * WEI;
                let balance = await erc20Contract.balanceOf(accounts[13])
                assert.equal(balance.toNumber(), calClaim, "Balance should be equal to the tokensPerInterval")

                calClaim = 1500 * WEI;
                balance = await erc20Contract.balanceOf(accounts[14])
                assert.equal(balance.toNumber(), calClaim, "Balance should be equal to the tokensPerInterval")
            })

            it('Should collect all eth',async function() {
                let balanceBefore = await web3.eth.getBalance(accounts[0])  
                balanceBefore = new BigNumber(balanceBefore)

                await crowdsaleContract.collect();              
                let balanceAfter = await web3.eth.getBalance(accounts[0]) 
                balanceAfter = new BigNumber(balanceAfter)

                assert.isAbove(balanceAfter.toNumber(),balanceBefore.toNumber(),"Balance should have increased")                
            })


            it('Should recover the left out tokens from the contract at stage 2', async function() {

                let isRecoverer  = await crowdsaleContract.isRecoverer(accounts[0])
                assert.equal(isRecoverer, true, " account 0 should be Recoverer")
                                
                await crowdsaleContract.recoverTokens(erc20Contract.address);
                let balanceAfter = await erc20Contract.balanceOf(crowdsaleContract.address)
                
                assert.equal(balanceAfter.toNumber(),0,"Balance should be 0")                
            
            })
        })
    })
    describe('Edge Case1 :  end crowdsale on reaching hardCap', function() {
    
        const intervals = 2;
        const guaranteedIntervals = 1;
        const hiddenCap = '100000000000000000000';
        const secretNumber = 1234;
        const ethPrice = 100 * 1e18  // 100 USD in 18 decimal point
        const floor = 1.0 * 1e17;
        const ceiling =  2 * 1e18;
        const reserveStart = 1 * 1e18;
        const crowdSaleAllocation = 1000 * WEI;

        describe('Reveal cap functions', function() {
            let firstBid = web3.utils.toWei(web3.utils.toBN(100),"ether");
            before(' Deploy erc20 contract', async function () {
                erc20Contract = await TBNERC20.new(TOTAL_SUPPLY, "Tubiex Network Token", "TBN", 18);
                hiddenCapHash = web3.utils.soliditySha3(hiddenCap,secretNumber)
                crowdsaleContract = await Crowdsale.new(erc20Contract.address, intervals, guaranteedIntervals, hiddenCapHash)
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
    
            it('Should add to whitelist', async function() {
                await crowdsaleContract.addToWhitelist([accounts[16]])
                let isWhitelist = await crowdsaleContract.whitelist(accounts[16])
                assert.equal(isWhitelist, true, "It should return true")
            })

            it('Should not reveal the hidden cap until cap is met', async function() {
                await crowdsaleContract.revealCap.call(hiddenCap, secretNumber).should.be.rejected;
            })

            it('Should participate in interval 0 ', async function(){
                await crowdsaleContract.participate(0,{from:accounts[16],value:firstBid})
            })

            it('Should create interval blocks', async function() {
                await manipulateBlocks(1);
            })

            it('Should be able to claim all the tokens', async function(){
                await crowdsaleContract.claim(0,{from: accounts[16]})
            })

            it('Should calculate the tokens allocated', async function() {
                tokenAllocated = 500 * WEI
                let balance = await erc20Contract.balanceOf(accounts[16])
                assert.equal(balance.toNumber(), tokenAllocated ,"Balnce should be equal to tokens allocated")
            })

            it('Should reveal the hidden cap when it is met', async function() {
               let revealCap =  await crowdsaleContract.revealCap.call(hiddenCap, secretNumber)
               assert.equal(revealCap,true,"revealCap should be true")
               
            })

        })

    })

    function manipulateBlocks(intervals) {
        return new Promise( async resolve => {
         let limit = claimPeriod * intervals;
         for(i =0; i<= limit; i++) {
            await crowdsaleContract.addToWhitelist([accounts[1],accounts[2],accounts[3]],{from: accounts[1]}).should.be.rejected;
        }
         resolve()
        })
    }
})

 