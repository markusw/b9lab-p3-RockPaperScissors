pragma solidity ^0.5.8;

import "./SafeMath.sol";
import "./Stoppable.sol";

contract RockPaperScissors is Stoppable {
    using SafeMath for uint;

    enum Moves {None, Rock, Paper, Scissors}

    uint public fee;
    uint public timeToEnd; // time player 1 has to end the game

    struct Game {
        uint bet;
        uint expiry;
        address player2;
        Moves move2;
    }

    mapping (address => uint) public balances;
    mapping (bytes32 => Game) public games;

    event LogNewGameStarted(
        address indexed player1,
        uint indexed bet,
        uint indexed expiry
    );
    event LogPlayer2Moved(
        address indexed player2,
        uint indexed bet,
        Moves indexed player2Move
    );
    event LogFeePaid(
        address indexed sender,
        uint amount
    );
    event LogGameDraw(
        address indexed player1,
        address indexed player2,
        uint indexed bet
    );
    event LogGameWinner(
        address indexed winner,
        uint indexed bet
    );
    event LogRefunded(
        address indexed refundAddress,
        uint indexed refundAmount
    );
    event LogWithdrawn(
        address indexed sender,
        uint amount
    );

    constructor(uint _fee, uint _timeToEnd, bool initialRunState) public Stoppable(initialRunState) {
        fee = _fee;
        timeToEnd = _timeToEnd;
    }

    function generateGameHash(Moves move, bytes32 secret) public view returns(bytes32 gameHash) {
        require(move != Moves.None, "Invalid move");

        return keccak256(abi.encodePacked(move, secret, msg.sender, address(this)));
    }

    function newGame(bytes32 gameHash, uint expiry) public payable onlyIfRunning returns(bool success) {
        // Player 1 starts a new game with the generated gameHash
        require(games[gameHash].expiry == 0, "Game already exists");
        require(expiry > 0, "Game expiry should be more than 0 seconds");

        uint betAmount;
        // Only substract fee if bet amount is higher than the fee
        if (msg.value > fee) {
            address owner = getOwner();
            balances[owner] = balances[owner].add(fee);
            betAmount = msg.value.sub(fee);

            emit LogFeePaid(msg.sender, fee);
        } else {
            betAmount = msg.value;
        }

        games[gameHash] = Game(
            betAmount,
            now.add(expiry),
            address(0x0),
            Moves.None
            );

        emit LogNewGameStarted(msg.sender, betAmount, expiry);

        return true;
    }

    function secondMove(bytes32 gameHash, Moves move2) public payable onlyIfRunning returns(bool success) {
        require(move2 != Moves.None, "Invalid move");
        uint betAmount;

        if (msg.value > fee) {
            address owner = getOwner();
            balances[owner] = balances[owner].add(fee);
            betAmount = msg.value.sub(fee);

            emit LogFeePaid(msg.sender, fee);
        } else {
            betAmount = msg.value;
        }

        require(games[gameHash].move2 == Moves.None, "Player 2 already moved");
        require(games[gameHash].bet == betAmount, "Bet of player 1 not matched");
        require(games[gameHash].expiry > now, "Game expired");

        games[gameHash].expiry = now.add(timeToEnd);
        games[gameHash].player2 = msg.sender;
        games[gameHash].move2 = move2;

        emit LogPlayer2Moved(msg.sender, betAmount, move2);

        return true;
    }

    function decideGame(Moves move, bytes32 secret) public onlyIfRunning returns(bool success) {
        bytes32 gameHash = generateGameHash(move, secret);
        Moves move2 = games[gameHash].move2;

        require(move2 != Moves.None, "Player 2 didn't make a move yet");
        require(games[gameHash].expiry > now, "Game expired or doesn't exist");

        address player2 = games[gameHash].player2;
        uint betAmount = games[gameHash].bet;

        if (move == move2) {
            balances[msg.sender] = balances[msg.sender].add(betAmount);
            balances[player2] = balances[player2].add(betAmount);

            emit LogGameDraw(msg.sender, player2, betAmount);
        } else {
            address winner;

            if (uint(move) == 1) {
                if (uint(move2) == 2) {
                    winner = player2;
                } else if (uint(move2) == 3) {
                    winner = msg.sender;
                }
            } else if (uint(move) == 2) {
                if (uint(move2) == 1) {
                    winner = msg.sender;
                } else if (uint(move2) == 3) {
                    winner = player2;
                }
            } else if (uint(move) == 3) {
                if (uint(move2) == 1) {
                    winner = player2;
                } else if (uint(move2) == 2) {
                    winner = msg.sender;
                }
            }

            balances[winner] = balances[winner].add(betAmount.mul(2));
            emit LogGameWinner(winner, betAmount);
        }

        delete games[gameHash].bet;
        delete games[gameHash].player2;
        delete games[gameHash].move2;

        return true;
    }

    function refundPlayer1(Moves move, bytes32 secret) public onlyIfRunning returns(bool success) {
        bytes32 gameHash = generateGameHash(move, secret);

        require(games[gameHash].move2 == Moves.None, "Player 2 made a move, can't refund");
        require(games[gameHash].expiry != 0, "Game with this secret and move doesn't exist");
        require(games[gameHash].expiry <= now, "Game isn't expired yet");

        uint refundAmount = games[gameHash].bet;

        balances[msg.sender] = balances[msg.sender].add(refundAmount);

        emit LogRefunded(msg.sender, refundAmount);

        delete games[gameHash].bet;

        return true;
    }

    function refundPlayer2(bytes32 gameHash) public onlyIfRunning returns(bool success) {
        address player2 = games[gameHash].player2;

        require(games[gameHash].move2 != Moves.None, "Game already finished or doesn't exist");
        require(player2 == msg.sender, "Only player 2 can close the game");
        require(games[gameHash].expiry <= now, "Game isn't expired yet");

        uint refundAmount = games[gameHash].bet.mul(2);
        // Player 2 can claim the whole bet amount since player 1 failed to verify
        balances[player2] = balances[player2].add(refundAmount);

        emit LogRefunded(msg.sender, refundAmount);

        delete games[gameHash].bet;
        delete games[gameHash].player2;
        delete games[gameHash].move2;

        return true;
    }

    function withdrawFunds() public onlyIfRunning returns(bool success) {
        uint withdrawAmount = balances[msg.sender];
        require(withdrawAmount > 0, "No balance to withdraw");

        emit LogWithdrawn(msg.sender, withdrawAmount);
        msg.sender.transfer(withdrawAmount);

        return true;
    }
}