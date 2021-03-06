const RockPaperScissors = artifacts.require("./RockPaperScissors.sol");
const helper = require("./helpers/truffleTestHelper");
const truffleAssert = require("truffle-assertions");

const { toBN } = web3.utils;

contract("RockPaperScissors", accounts => {
    const [owner, player1, player2, otherAddress] = accounts;
    const fee = 100;
    const timeToEnd = 3600;
    const secret = "0x70617373776f7264";
    const expiry = 600;
    const moves = {
        "None": 0,
        "Rock": 1,
        "Paper": 2,
        "Scissors": 3
    };

    beforeEach("Get new contract before each test", async () => {
        instance = await RockPaperScissors.new(fee, timeToEnd, true, {from: owner});
        gameHash = await instance.generateGameHash(moves["Rock"], secret, player1, {from: player1});
        betAmount = 500;
    });

    describe("Test game bets", async () => {
        it("Should be possible to start new game and pay fees", async () => {

            const txObj = await instance.newGame(gameHash, expiry, {from: player1, value: betAmount});

            // check number of events
            assert.equal(txObj.logs.length, 2, "Wrong number of events");
            // check order of events
            assert.equal(txObj.logs[0].event, "LogFeePaid");
            assert.equal(txObj.logs[1].event, "LogNewGameStarted");
            // check event
            truffleAssert.eventEmitted(txObj, "LogNewGameStarted", {
                gameHash: gameHash,
                player1: player1, 
                bet: toBN(betAmount - fee), 
                expiry: toBN(expiry)
            });
            truffleAssert.eventEmitted(txObj, "LogFeePaid", {gameHash: gameHash, sender: player1, amount: toBN(fee)});

            // check fee
            const feeBalance = await instance.balances(owner);
            assert.equal(fee.toString(), feeBalance.toString(), "Didn't credit fee correctly");

            // balance of gameHash should be bet amount - fees
            const game = await instance.games(gameHash);
            assert.equal(game.bet.toString(), (betAmount - fee).toString(), "Didn't credit bet amount correctly");
        });

        it("Should be possible for player 2 to join the game", async () => {
            await instance.newGame(gameHash, expiry, {from: player1, value: betAmount});

            const txObj = await instance.joinGame(gameHash, {from: player2, value: betAmount});

            // check event
            truffleAssert.eventEmitted(txObj, "LogFeePaid", {gameHash: gameHash, sender: player2, amount: toBN(fee)});
            truffleAssert.eventEmitted(txObj, "LogPlayer2Joined", {gameHash: gameHash, player2: player2});

            const game = await instance.games(gameHash);
            assert.equal(game.player2, player2);

        });

        it("Should only be possible for player 2 to make a move", async () => {
            await instance.newGame(gameHash, expiry, {from: player1, value: betAmount});
            await instance.joinGame(gameHash, {from: player2, value: betAmount});

            try {
                await instance.secondMove(gameHash, moves["Paper"], {from: otherAddress});
            }
            catch (err) {
                assert.equal(err.reason, "Only player 2 can make a move");
            }
            
            const txObj = await instance.secondMove(gameHash, moves["Paper"], {from: player2});

            // check event
            truffleAssert.eventEmitted(txObj, "LogPlayer2Moved", {gameHash: gameHash, player2: player2, player2Move: toBN(moves["Paper"])});

            const game = await instance.games(gameHash);
            assert.equal(game.move2, moves["Paper"], "Saved wrong move");
        });

        it("Should let player 1 end the game after both players made a move", async () => {
            await instance.newGame(gameHash, expiry, {from: player1, value: betAmount});
            await instance.joinGame(gameHash, {from: player2, value: betAmount});
            await instance.secondMove(gameHash, moves["Paper"], {from: player2});

            const txObj = await instance.decideGame(moves["Rock"], secret, {from: player1})

            // check event
            truffleAssert.eventEmitted(txObj, "LogGameWinner", {gameHash: gameHash, winner: player2, bet: toBN(betAmount - fee)});

            const winnerBalance = await instance.balances(player2);
            const winningAmount = (toBN(betAmount).sub(toBN(fee))).mul(toBN(2));

            assert.equal(winnerBalance.toString(), winningAmount.toString(), "Didn't credit winner correctly");
        });
    });
    describe("Test refunds for failed games", async () => {
        it("Should refund p1 bet if p2 doesn't make a move before deadline", async () => {
            await instance.newGame(gameHash, expiry, {from: player1, value: betAmount});

            // Shouldn't work before deadline is over
            try {
                await instance.refundPlayer1(moves["Rock"], secret, {from: player1});
            }
            catch (err) {
                assert.equal(err.reason, "Game isn't expired yet")
            }

            // move time
            await helper.advanceTimeAndBlock(expiry + 1);

            const txObj = await instance.refundPlayer1(moves["Rock"], secret, {from: player1});

            // check event
            truffleAssert.eventEmitted(txObj, "LogRefunded", {gameHash: gameHash, refundAddress: player1, refundAmount: toBN(betAmount - fee)});

            // check balance after refund
            const newBalance = await instance.balances(player1)
            assert.equal(newBalance.toString(), (betAmount - fee).toString());
        });

        it("Should refund p2 if p1 fails to close the game", async () => {
            await instance.newGame(gameHash, expiry, {from: player1, value: betAmount});
            await instance.joinGame(gameHash, {from: player2, value: betAmount});
            await instance.secondMove(gameHash, moves["Paper"], {from: player2});

            // Shouldn't work if not expired
            try {
                await instance.refundPlayer2(gameHash, {from: player2});
            }
            catch (err) {
                assert.equal(err.reason, "Game isn't expired yet");
            }

            await helper.advanceTimeAndBlock(timeToEnd + 1);

            const txObj = await instance.refundPlayer2(gameHash, {from: player2});
            const refundAmount = (toBN(betAmount).sub(toBN(fee))).mul(toBN(2));

            truffleAssert.eventEmitted(txObj, "LogRefunded", {gameHash: gameHash, refundAddress: player2, refundAmount: refundAmount});

            const p2Balance = await instance.balances(player2);
            assert.equal(p2Balance.toString(), refundAmount.toString());
        });
    });
    describe("Test game logic", async () => {
        it("Should handle a draw correctly", async () => {
            await instance.newGame(gameHash, expiry, {from: player1, value: betAmount});
            await instance.joinGame(gameHash, {from: player2, value: betAmount});
            await instance.secondMove(gameHash, moves["Rock"], {from: player2});

            const txObj = await instance.decideGame(moves["Rock"], secret, {from: player1})

            // check event
            truffleAssert.eventEmitted(txObj, "LogGameDraw", {gameHash: gameHash, player1: player1, player2: player2, bet: toBN(betAmount - fee)});

            // check balances
            const p1Balance = await instance.balances(player1);
            assert.equal(p1Balance.toString(), (betAmount - fee).toString());
            const p2Balance = await instance.balances(player2);
            assert.equal(p2Balance.toString(), (betAmount - fee).toString());
        });

        it("Rock should beat scissors", async () => {
            await instance.newGame(gameHash, expiry, {from: player1, value: betAmount});
            await instance.joinGame(gameHash, {from: player2, value: betAmount});
            await instance.secondMove(gameHash, moves["Scissors"], {from: player2});

            const txObj = await instance.decideGame(moves["Rock"], secret, {from: player1})

            truffleAssert.eventEmitted(txObj, "LogGameWinner", {gameHash: gameHash, winner: player1, bet: toBN(betAmount - fee)});

            const winningAmount = (toBN(betAmount).sub(toBN(fee))).mul(toBN(2));
            const winnerBalance = await instance.balances(player1);

            assert.equal(winningAmount.toString(), winnerBalance.toString());
        });

        it("Scissors should beat paper", async () => {
            const gameHash = await instance.generateGameHash(moves["Scissors"], secret, player1, {from: player1});
            await instance.newGame(gameHash, expiry, {from: player1, value: betAmount});
            await instance.joinGame(gameHash, {from: player2, value: betAmount});
            await instance.secondMove(gameHash, moves["Paper"], {from: player2});

            const txObj = await instance.decideGame(moves["Scissors"], secret, {from: player1})

            truffleAssert.eventEmitted(txObj, "LogGameWinner", {gameHash: gameHash, winner: player1, bet: toBN(betAmount - fee)});

            const winningAmount = (toBN(betAmount).sub(toBN(fee))).mul(toBN(2));
            const winnerBalance = await instance.balances(player1);

            assert.equal(winningAmount.toString(), winnerBalance.toString());
        });

        it("Paper should beat Rock", async () => {
            await instance.newGame(gameHash, expiry, {from: player1, value: betAmount});
            await instance.joinGame(gameHash, {from: player2, value: betAmount});
            await instance.secondMove(gameHash, moves["Paper"], {from: player2});

            const txObj = await instance.decideGame(moves["Rock"], secret, {from: player1});

            truffleAssert.eventEmitted(txObj, "LogGameWinner", {gameHash: gameHash, winner: player2, bet: toBN(betAmount - fee)});

            const winningAmount = (toBN(betAmount).sub(toBN(fee))).mul(toBN(2));
            const winnerBalance = await instance.balances(player2);

            assert.equal(winningAmount.toString(), winnerBalance.toString());
        });
    });
    describe("Test withdrawal of balance", async () => {
        it("Should be possible for players to withdraw their balance", async () => {
            // play game
            await instance.newGame(gameHash, expiry, {from: player1, value: betAmount});
            await instance.joinGame(gameHash, {from: player2, value: betAmount});
            await instance.secondMove(gameHash, moves["Paper"], {from: player2});
            await instance.decideGame(moves["Rock"], secret, {from: player1});

            const balanceBefore = toBN(await web3.eth.getBalance(player2));
            const withdrawBalance = await instance.balances(player2);

            // player 1 has no funds, shouldn't be able to withdraw
            try {
                await instance.withdrawFunds({from: player1});
            } 
            catch (err) {
                assert.equal(err.reason, "No balance to withdraw");
            }

            const txObj = await instance.withdrawFunds({from: player2});
            truffleAssert.eventEmitted(txObj, "LogWithdrawn", {sender: player2, amount: withdrawBalance});

            // calculate tx cost
            const gasUsed = toBN(txObj.receipt.gasUsed);
            const gasPrice = toBN((await web3.eth.getTransaction(txObj.tx)).gasPrice);
            const txCost = toBN(gasPrice).mul(gasUsed);
            // expected balance
            const ethExpected = balanceBefore.add(toBN(withdrawBalance).sub(txCost));

            const actualBalance = toBN(await web3.eth.getBalance(player2));

            assert.equal(ethExpected.toString(), actualBalance.toString());
        });

        it("Should be possible for owner to withdraw fees", async () => {
            // play game
            await instance.newGame(gameHash, expiry, {from: player1, value: betAmount});
            await instance.joinGame(gameHash, {from: player2, value: betAmount});
            await instance.secondMove(gameHash, moves["Paper"], {from: player2});
            await instance.decideGame(moves["Rock"], secret, {from: player1});

            const feesPaid = toBN(fee * 2);

            const txObj = await instance.withdrawFunds({from: owner});

            truffleAssert.eventEmitted(txObj, "LogWithdrawn", {sender: owner, amount: feesPaid});
        });
    });
});