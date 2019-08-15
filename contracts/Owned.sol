pragma solidity ^0.5.0;

contract Owned {
    address private owner;

    event LogChangeOwner(address indexed sender, address indexed newOwner);

    modifier onlyOwner {
        require(msg.sender == owner, "Sender not authorized");
        _;
    }

    constructor() public {
        owner = msg.sender;
    }

    function changeOwner(address newOwner) public onlyOwner returns(bool success) {
        require(newOwner != address(0x0), "New Owner can't be empty address");
        require(newOwner != owner, "Already the owner");

        owner = newOwner;

        emit LogChangeOwner(msg.sender, newOwner);

        return true;
    }

    function getOwner() public view returns(address) {
        return owner;
    }
}