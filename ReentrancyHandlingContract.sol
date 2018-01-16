pragma solidity ^0.4.19;

contract ReentrancyHandlingContract {

    bool locked;

    modifier noReentrancy() {
        require(!locked);
        locked = true;
        _;
        locked = false;
    }
}

