const RockPaperScissors = artifacts.require("./RockPaperScissors.sol");
const truffleAssert = require("truffle-assertions");

const { toBN } = web3.utils;

contract("RockPaperScissors", accounts => {
    const [owner, otherAddress] = accounts;

    beforeEach("Get new Instance before each test", async () => {
        instance = await RockPaperScissors.new(100, 3600, true, {from: owner});
    });

    describe("Changing owner", async() => {
        it("Should be possible to change owner", async() => {
            // change owner to otherAddress
            const txObj = await instance.changeOwner(otherAddress, {from: owner});

            // get owner of contract
            const newOwner = await instance.getOwner();

            assert.equal(otherAddress, newOwner, "Owner not changed correctly");

            // test event
            truffleAssert.eventEmitted(txObj, "LogChangeOwner", (ev) => { 
                return ev.sender == owner && ev.newOwner == otherAddress;
            });
        });

        it("Non-owner shouldn't be able to change contract owner", async() => {
            try {
                const txObj = await instance.changeOwner(otherAddress, {from: otherAddress});
                truffleAssert.eventNotEmitted(txObj, 'LogChangeOwner');
            }
            catch (err) {
                assert.equal(err.reason, "Sender not authorized");
            }
        });
    });

    describe("Pausing and killing contract", async() => {
        it("Should be possible to pause contract", async() => {
            // pause the contract
            const txObj = await instance.pauseContract({from: owner});
            // get status
            const contractStatus = await instance.isRunning();

            assert.equal(contractStatus, false);

            // test event
            truffleAssert.eventEmitted(txObj, "LogPausedContract", (ev) => { 
                return ev.sender == owner;
            });
        });
        
        it("Should be possible to kill contract", async() => {
            // pause then kill the contract
            await instance.pauseContract({from: owner});
            const txObj = await instance.killContract({from: owner});

            // test event
            truffleAssert.eventEmitted(txObj, "LogKilledContract", {sender: owner})

            // check if contract can be resumed
            try {
                await instance.resume();
            } 
            catch (err) {
                assert.equal(err.reason, "Contract is killed");
            }

            assert.equal(await instance.isRunning(), false);
        });

        it("Non-owner shouldn't be able to pause or resume the contract", async() => {
            try {
                const txObj = await instance.pauseContract({from: otherAddress});
                truffleAssert.eventNotEmitted(txObj, 'LogPausedContract');
            }
            catch (err) {
                assert.equal(err.reason, "Sender not authorized");
            }
        });
        
        it("Should not be possible to kill running contract", async() => {
            try {
                const txObj = await instance.killContract({from: owner});
                truffleAssert.eventNotEmitted(txObj, 'LogKilledContract');
            }
            catch (err) {
                assert.equal(err.reason, "Is not paused");
            }
        });
    });
});