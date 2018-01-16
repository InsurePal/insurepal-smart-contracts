pragma solidity ^0.4.19;

import "ReentrancyHandlingContract.sol";
import "Owned.sol";
import "InsurePalTokenInterface.sol";
import "ERC20TokenInterface.sol";
import "KycContractInterface.sol";

contract Crowdsale is ReentrancyHandlingContract, Owned {

  struct ContributorData {
    uint contributionAmount;
    uint tokensIssued;
  }

  mapping(address => ContributorData) public contributorList;
  uint nextContributorIndex;
  mapping(uint => address) contributorIndexes;

  state public crowdsaleState = state.pendingStart;
  enum state { pendingStart, crowdsale, crowdsaleEnded }

  uint public crowdsaleStartBlock;
  uint public crowdsaleEndedBlock;

  event CrowdsaleStarted(uint blockNumber);
  event CrowdsaleEnded(uint blockNumber);
  event ErrorSendingETH(address to, uint amount);
  event MinCapReached(uint blockNumber);
  event MaxCapReached(uint blockNumber);

  address tokenAddress = 0x0;
  address kycAddress = 0x0;
  uint decimals = 18;

  uint public minCap; //InTokens
  uint public maxCap; //InTokens
  uint public ethRaised;
  uint public tokenTotalSupply = 300000000 * 10**decimals;
  uint public tokensIssued = 0;

  address public multisigAddress;
  uint blocksInADay;

  uint nextContributorToClaim;
  mapping(address => bool) hasClaimedEthWhenFail;

  uint crowdsaleTokenCap =          201000000 * 10**decimals;
  uint founders =                    30000000 * 10**decimals;
  uint insurePalTeam =               18000000 * 10**decimals;
  uint tcsSupportTeam =              18000000 * 10**decimals;
  uint advisorsAndAmbassadors =      18000000 * 10**decimals;
  uint incentives =                   9000000 * 10**decimals;
  uint earlyInvestors =               6000000 * 10**decimals;
  bool foundersTokensClaimed = false;
  bool insurePalTeamTokensClaimed = false;
  bool tcsSupportTeamTokensClaimed = false;
  bool advisorsAndAmbassadorsTokensClaimed = false;
  bool incentivesTokensClaimed = false;
  bool earlyInvestorsTokensClaimed = false;

  //
  // Unnamed function that runs when eth is sent to the contract
  //
  function() noReentrancy payable public {
    require(msg.value != 0);                        // Throw if value is 0
    require(crowdsaleState != state.crowdsaleEnded);// Check if crowdsale has ended
    require(KycContractInterface(kycAddress).isAddressVerified(msg.sender));

    bool stateChanged = checkCrowdsaleState();      // Check blocks and calibrate crowdsale state

    if (crowdsaleState == state.crowdsale) {
      processTransaction(msg.sender, msg.value);    // Process transaction and issue tokens
    } else {
      refundTransaction(stateChanged);              // Set state and return funds or throw
    }
  }

  //
  // Check crowdsale state and calibrate it
  //
  function checkCrowdsaleState() internal returns (bool) {
    if (tokensIssued == maxCap && crowdsaleState != state.crowdsaleEnded) {                     // Check if max cap is reached
      crowdsaleState = state.crowdsaleEnded;
      CrowdsaleEnded(block.number);                                                             // Raise event
      return true;
    }

    if (block.number >= crowdsaleStartBlock && block.number <= crowdsaleEndedBlock) {            // Check if we are in crowdsale state
      if (crowdsaleState != state.crowdsale) {                                                  // Check if state needs to be changed
        crowdsaleState = state.crowdsale;                                                       // Set new state
        CrowdsaleStarted(block.number);                                                         // Raise event
        return true;
      }
    } else {
      if (crowdsaleState != state.crowdsaleEnded && block.number > crowdsaleEndedBlock) {       // Check if crowdsale is over
        crowdsaleState = state.crowdsaleEnded;                                                  // Set new state
        CrowdsaleEnded(block.number);                                                           // Raise event
        return true;
      }
    }
    return false;
  }

  //
  // Decide if throw or only return ether
  //
  function refundTransaction(bool _stateChanged) internal {
    if (_stateChanged) {
      msg.sender.transfer(msg.value);
    } else {
      revert();
    }
  }

  function calculateEthToToken(uint _eth, uint _blockNumber) constant public returns(uint) {
    if (_blockNumber < crowdsaleStartBlock + blocksInADay * 4) {
      return _eth * 12817;
    }
    if (_eth >= 50*10**decimals) {
      return _eth * 12817;
    }
    if (_blockNumber > crowdsaleStartBlock) {
      return _eth * 11652;
    }
  }

  function calculateTokenToEth(uint _token, uint _blockNumber) constant public returns(uint) {
    if (_blockNumber < crowdsaleStartBlock + blocksInADay * 4) {
      return _token * 10000 / 12817;
    }
    if (_token >= 50*12817*10**decimals) {
      return _token * 10000 / 12817;
    }
    if (_blockNumber > crowdsaleStartBlock) {
      return _token * 10000 / 11652;
    }
  }

  //
  // Issue tokens and return if there is overflow
  //

  function processTransaction(address _contributor, uint _amount) internal {
    uint contributionAmount = _amount;
    uint returnAmount = 0;
    uint tokensToGive = calculateEthToToken(contributionAmount, block.number);

    if (tokensToGive > (maxCap - tokensIssued)) {                                     // Check if max contribution is lower than _amount sent
      contributionAmount = calculateTokenToEth(maxCap - tokensIssued, block.number) / 10000;  // Set that user contibutes his maximum alowed contribution
      returnAmount = _amount - contributionAmount;                                    // Calculate howmuch he must get back
      tokensToGive = maxCap - tokensIssued;
      MaxCapReached(block.number);
    }

    if (contributorList[_contributor].contributionAmount == 0) {
        contributorIndexes[nextContributorIndex] = _contributor;
        nextContributorIndex += 1;
    }

    contributorList[_contributor].contributionAmount += contributionAmount;
    ethRaised += contributionAmount;                                              // Add to eth raised

    if (tokensToGive > 0) {
      InsurePalTokenInterface(tokenAddress).mint(_contributor, tokensToGive);       // Issue new tokens
      contributorList[_contributor].tokensIssued += tokensToGive;                  // log token issuance
      tokensIssued += tokensToGive;
    }
    if (returnAmount != 0) {
      _contributor.transfer(returnAmount);
    } 
  }

  function pushAngelInvestmentData(address _address, uint _ethContributed) onlyOwner public {
      processTransaction(_address, _ethContributed);
  }

  function depositAngelInvestmentEth() payable onlyOwner public {}
  

  //
  // Method is needed for recovering tokens accedentaly sent to token address
  //
  function salvageTokensFromContract(address _tokenAddress, address _to, uint _amount) onlyOwner public {
    ERC20TokenInterface(_tokenAddress).transfer(_to, _amount);
  }

  //
  // withdrawEth when minimum cap is reached
  //
  function withdrawEth() onlyOwner public {
    require(this.balance != 0);
    require(tokensIssued >= minCap);

    multisigAddress.transfer(this.balance);
  }

  //
  // Users can claim their contribution if min cap is not raised
  //
  function claimEthIfFailed() public {
    require(block.number > crowdsaleEndedBlock && tokensIssued < minCap);    // Check if crowdsale has failed
    require(contributorList[msg.sender].contributionAmount > 0);          // Check if contributor has contributed to crowdsaleEndedBlock
    require(!hasClaimedEthWhenFail[msg.sender]);                          // Check if contributor has already claimed his eth

    uint ethContributed = contributorList[msg.sender].contributionAmount; // Get contributors contribution
    hasClaimedEthWhenFail[msg.sender] = true;                             // Set that he has claimed
    if (!msg.sender.send(ethContributed)) {                                // Refund eth
      ErrorSendingETH(msg.sender, ethContributed);                        // If there is an issue raise event for manual recovery
    }
  }

  //
  // Owner can batch return contributors contributions(eth)
  //
  function batchReturnEthIfFailed(uint _numberOfReturns) onlyOwner public {
    require(block.number > crowdsaleEndedBlock && tokensIssued < minCap);                // Check if crowdsale has failed
    address currentParticipantAddress;
    uint contribution;
    for (uint cnt = 0; cnt < _numberOfReturns; cnt++) {
      currentParticipantAddress = contributorIndexes[nextContributorToClaim];         // Get next unclaimed participant
      if (currentParticipantAddress == 0x0) {
        return;                                                                       // Check if all the participants were compensated
      }
      if (!hasClaimedEthWhenFail[currentParticipantAddress]) {                        // Check if participant has already claimed
        contribution = contributorList[currentParticipantAddress].contributionAmount; // Get contribution of participant
        hasClaimedEthWhenFail[currentParticipantAddress] = true;                      // Set that he has claimed
        if (!currentParticipantAddress.send(contribution)) {                          // Refund eth
          ErrorSendingETH(currentParticipantAddress, contribution);                   // If there is an issue raise event for manual recovery
        }
      }
      nextContributorToClaim += 1;                                                    // Repeat
    }
  }

  //
  // If there were any issue/attach with refund owner can withraw eth at the end for manual recovery
  //
  function withdrawRemainingBalanceForManualRecovery() onlyOwner public {
    require(this.balance != 0);                                  // Check if there are any eth to claim
    require(block.number > crowdsaleEndedBlock);                 // Check if crowdsale is over
    require(contributorIndexes[nextContributorToClaim] == 0x0);  // Check if all the users were refunded
    multisigAddress.transfer(this.balance);                      // Withdraw to multisig
  }

  function claimTeamTokens(address _to, uint _choice) onlyOwner public {
    require(crowdsaleState == state.crowdsaleEnded);
    require(tokensIssued >= minCap);

    uint mintAmount;
    if (_choice == 1) {
      assert(!insurePalTeamTokensClaimed);
      mintAmount = insurePalTeam;
      insurePalTeamTokensClaimed = true;
    } else if (_choice == 2) {
      assert(!tcsSupportTeamTokensClaimed);
      mintAmount = tcsSupportTeam;
      tcsSupportTeamTokensClaimed = true;
    } else if (_choice == 3) {
      assert(!advisorsAndAmbassadorsTokensClaimed);
      mintAmount = advisorsAndAmbassadors;
      advisorsAndAmbassadorsTokensClaimed = true;
    } else if (_choice == 4) {
      assert(!incentivesTokensClaimed);
      mintAmount = incentives;
      incentivesTokensClaimed = true;
    } else if (_choice == 5) {
      assert(!earlyInvestorsTokensClaimed);
      mintAmount = earlyInvestors;
      earlyInvestorsTokensClaimed = true;
    } else if (_choice == 6) {
      assert(!foundersTokensClaimed);
      assert(insurePalTeamTokensClaimed);
      assert(tcsSupportTeamTokensClaimed);
      assert(advisorsAndAmbassadorsTokensClaimed);
      assert(incentivesTokensClaimed);
      assert(earlyInvestorsTokensClaimed);
      assert(tokenTotalSupply > ERC20TokenInterface(tokenAddress).totalSupply());
      mintAmount = tokenTotalSupply - ERC20TokenInterface(tokenAddress).totalSupply();
      foundersTokensClaimed = true;
    } else {
      revert();
    }
    InsurePalTokenInterface(tokenAddress).mint(_to, mintAmount);
  }

  //
  // Owner can set multisig address for crowdsale
  //
  function setMultisigAddress(address _newAddress) onlyOwner public {
    multisigAddress = _newAddress;
  }

  //
  // Owner can set token address where mints will happen
  //
  function setToken(address _newAddress) onlyOwner public {
    tokenAddress = _newAddress;
  }

  function setKycAddress(address _newAddress) onlyOwner public {
    kycAddress = _newAddress;
  }

  function getTokenAddress() constant public returns(address) {
    return tokenAddress;
  }

  function investorCount() constant public returns(uint) {
    return nextContributorIndex;
  }

  function setCrowdsaleStartBlock(uint _block) onlyOwner public {
    crowdsaleStartBlock = _block;
  }
}



