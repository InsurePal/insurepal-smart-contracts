pragma solidity ^0.4.19;

import "Crowdsale.sol";


contract InsurePalCrowdsale is Crowdsale {
  
  function InsurePalCrowdsale() {

    crowdsaleStartBlock = 4918135;
    crowdsaleEndedBlock = 5031534; 

    minCap = 50000000 * 10**18;
    maxCap = 201000000 * 10**18;

    blocksInADay = 5400;
  }
}