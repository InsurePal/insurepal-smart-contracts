pragma solidity ^0.4.19;

import "ERC20Token.sol";

contract InsurePalToken is ERC20Token {

  /* Initializes contract */
  function InsurePalToken() {
    standard = "InsurePal token v1.0";
    name = "InsurePal token";
    symbol = "IPL";
    decimals = 18;
    crowdsaleContractAddress = 0x0c411ffFc6d3a8E4ca5f81bBC98b5B3EdA8FC3C7;   
    lockFromSelf(5031534, "Lock before crowdsale starts");
  }
}
