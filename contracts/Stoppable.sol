pragma solidity ^0.5.0;

import "./Owned.sol";

contract Stoppable is Owned {
    bool private running;
    bool private killed;

    event LogPausedContract(address sender);
    event LogResumedContract(address sender);
    event LogKilledContract(address sender);

    modifier onlyIfRunning {
        require(running, "Is not running");
        _;
    }

    modifier onlyIfPaused {
        require(!running, "Is not paused");
        _;
    }

    modifier onlyIfAlive {
        require(!killed, "Contract is killed");
        _;
    }

    constructor(bool initialRunState) public {
        running = initialRunState;
    }

    function pauseContract() public onlyOwner onlyIfRunning returns(bool success) {
        running = false;
        emit LogPausedContract(msg.sender);
        return true;
    }

    function resume() public onlyOwner onlyIfPaused onlyIfAlive returns(bool success) {
        running = true;
        emit LogResumedContract(msg.sender);
        return true;
    }

    function killContract() public onlyOwner onlyIfPaused returns(bool success) {
        killed = true;
        emit LogKilledContract(msg.sender);
        return true;
    }

    function isRunning() public view returns(bool) {
        return running;
    }

    function isKilled() public view returns(bool) {
        return killed;
    }
}