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
        uint deadline;
        address player2;
        Moves move2;
    }

    mapping (address => uint) public balances;
    mapping (bytes32 => Game) public games;

    event LogNewGameStarted(
        bytes32 indexed gameHash,
        address indexed player1,
        uint bet,
        uint expiry
    );
    event LogPlayer2Joined(
        bytes32 indexed gameHash,
        address indexed player2
    );
    event LogPlayer2Moved(
        bytes32 indexed gameHash,
        address indexed player2,
        Moves indexed player2Move
    );
    event LogFeePaid(
        bytes32 indexed gameHash,
        address indexed sender,
        uint amount
    );
    event LogGameDraw(
        bytes32 indexed gameHash,
        address indexed player1,
        address indexed player2,
        uint bet
    );
    event LogGameWinner(
        bytes32 indexed gameHash,
        address indexed winner,
        uint bet
    );
    event LogRefunded(
        bytes32 indexed gameHash,
        address indexed refundAddress,
        uint refundAmount
    );
    event LogWithdrawn(
        address indexed sender,
        uint amount
    );

    constructor(uint _fee, uint _timeToEnd, bool initialRunState) public Stoppable(initialRunState) {
        fee = _fee;
        timeToEnd = _timeToEnd;
    }

    function generateGameHash(Moves move, bytes32 secret, address player1) public view returns(bytes32 gameHash) {
        require(move != Moves.None, "Invalid move");

        return keccak256(abi.encodePacked(move, secret, player1, address(this)));
    }

    function newGame(bytes32 gameHash, uint expiry) public payable onlyIfRunning returns(bool success) {
        // Player 1 starts a new game with the generated gameHash
        require(games[gameHash].deadline == 0, "Game already exists");
        require(expiry > 0, "Game expiry should be more than 0 seconds");

        uint betAmount;
        // Only substract fee if bet amount is higher than the fee
        if (msg.value > fee) {
            address owner = getOwner();
            balances[owner] = balances[owner].add(fee);
            betAmount = msg.value.sub(fee);

            emit LogFeePaid(gameHash, msg.sender, fee);
        } else {
            betAmount = msg.value;
        }

        games[gameHash].bet = betAmount;
        games[gameHash].deadline = now.add(expiry);

        emit LogNewGameStarted(gameHash, msg.sender, betAmount, expiry);

        return true;
    }

    function joinGame(bytes32 gameHash) public payable onlyIfRunning returns(bool success) {
        // player 2 needs to join the game before making a move to avoid front-running
        require(games[gameHash].player2 == address(0x0), "Someone already joined this game");
        require(games[gameHash].deadline > now, "Game expired or doesn't exist");

        uint betAmount;

        if (msg.value > fee) {
            address owner = getOwner();
            balances[owner] = balances[owner].add(fee);
            betAmount = msg.value.sub(fee);

            emit LogFeePaid(gameHash, msg.sender, fee);
        } else {
            betAmount = msg.value;
        }

        require(games[gameHash].bet == betAmount, "Bet of player 1 not matched");

        games[gameHash].player2 = msg.sender;

        emit LogPlayer2Joined(gameHash, msg.sender);

        return true;
    }

    function secondMove(bytes32 gameHash, Moves move2) public onlyIfRunning returns(bool success) {
        require(move2 != Moves.None, "Invalid move");
        require(games[gameHash].deadline > now, "Game expired or doesn't exist");
        require(games[gameHash].player2 == msg.sender, "Only player 2 can make a move");
        require(games[gameHash].move2 == Moves.None, "Player 2 already moved");

        games[gameHash].deadline = now.add(timeToEnd);
        games[gameHash].move2 = move2;

        emit LogPlayer2Moved(gameHash, msg.sender, move2);

        return true;
    }

    function decideGame(Moves move, bytes32 secret) public onlyIfRunning returns(bool success) {
        bytes32 gameHash = generateGameHash(move, secret, msg.sender);
        Moves move2 = games[gameHash].move2;

        require(move2 != Moves.None, "Player 2 didn't make a move yet");

        address player2 = games[gameHash].player2;
        uint betAmount = games[gameHash].bet;

        if (move == move2) {
            balances[msg.sender] = balances[msg.sender].add(betAmount);
            balances[player2] = balances[player2].add(betAmount);

            emit LogGameDraw(gameHash, msg.sender, player2, betAmount);
        } else {
            address winner;

            if (move == Moves.Rock) {
                if (move2 == Moves.Paper) {
                    winner = player2;
                } else if (move2 == Moves.Scissors) {
                    winner = msg.sender;
                } else {
                    revert("Invalid move");
                }
            } else if (move == Moves.Paper) {
                if (move2 == Moves.Rock) {
                    winner = msg.sender;
                } else if (move2 == Moves.Scissors) {
                    winner = player2;
                } else {
                    revert("Invalid move");
                }
            } else if (move == Moves.Scissors) {
                if (move2 == Moves.Rock) {
                    winner = player2;
                } else if (move2 == Moves.Paper) {
                    winner = msg.sender;
                } else {
                    revert("Invalid move");
                }
            } else {
                revert("Invalid move");
            }

            balances[winner] = balances[winner].add(betAmount.mul(2));
            emit LogGameWinner(gameHash, winner, betAmount);
        }

        delete games[gameHash].bet;
        delete games[gameHash].player2;
        delete games[gameHash].move2;

        return true;
    }

    function refundPlayer1(Moves move, bytes32 secret) public onlyIfRunning returns(bool success) {
        bytes32 gameHash = generateGameHash(move, secret, msg.sender);

        require(games[gameHash].move2 == Moves.None, "Player 2 made a move, can't refund");
        require(games[gameHash].deadline != 0, "Game with this secret and move doesn't exist");
        require(games[gameHash].deadline <= now, "Game isn't expired yet");

        uint refundAmount = games[gameHash].bet;

        balances[msg.sender] = balances[msg.sender].add(refundAmount);

        emit LogRefunded(gameHash, msg.sender, refundAmount);

        delete games[gameHash].bet;
        delete games[gameHash].player2;
        delete games[gameHash].move2;

        return true;
    }

    function refundPlayer2(bytes32 gameHash) public onlyIfRunning returns(bool success) {
        address player2 = games[gameHash].player2;

        require(games[gameHash].move2 != Moves.None, "Game already finished or doesn't exist");
        require(player2 == msg.sender, "Only player 2 can close the game");
        require(games[gameHash].deadline <= now, "Game isn't expired yet");

        uint refundAmount = games[gameHash].bet.mul(2);
        // Player 2 can claim the whole bet amount since player 1 failed to verify
        balances[player2] = balances[player2].add(refundAmount);

        emit LogRefunded(gameHash, msg.sender, refundAmount);

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