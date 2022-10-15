

// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

/*    
🅣🅗🅔🅡🅐🅝🅒🅗_🅑🅤🅛🅛🅢_➋⓿➋➋
*/


import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

import "./TheRanchBTCBullsCommunity.sol";


error Raffle__UpkeepNotNeeded (uint256 USDCRewardsBalance, uint256 numPlayers, uint256 raffleMintState);

contract TheRanchBTCBullsChainLinkVRF is VRFConsumerBaseV2, Ownable {


    address public TheRanchBTCBullsCommunityAddress;

    mapping(address => bool) public isDefenderRole;



    modifier ADMIN_OR_DEFENDER {
        require(msg.sender == owner() || isDefenderRole[msg.sender] == true, "Caller is not an OWNER OR DEFENDER");
        _;
    }


    modifier TRBC_contract_only {
        require(msg.sender ==  TheRanchBTCBullsCommunityAddress, "Not authorized to call");
        _;
    }









    // Chainlink VRF Variables
    VRFCoordinatorV2Interface private  vrfCoordinator;
    uint64 private subscriptionId;
    bytes32 private gasLane;
    uint32 private callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;


    constructor(
        address _vrfCoordinatorV2,
        bytes32 _gasLane, // keyHash
        uint64 _subscriptionId,
        uint32 _callbackGasLimit
    ) 
        VRFConsumerBaseV2(_vrfCoordinatorV2) {

        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinatorV2);
        gasLane = _gasLane;
        subscriptionId = _subscriptionId;
        callbackGasLimit = _callbackGasLimit;
    }


    // function getRaffleWinner() public TRBC_contract_only {
    //         uint256 requestId = vrfCoordinator.requestRandomWords(
    //         gasLane,
    //         subscriptionId,
    //         REQUEST_CONFIRMATIONS,
    //         callbackGasLimit,
    //         NUM_WORDS
    //     );
    //     //emit RequestedRaffleWinner(requestId);
    // }

    /**
        * @dev This is the function that Chainlink VRF node
        * calls to send the money to the random winner.
        */
    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        // dailyRafflePlayers size 10
        // randomNumber 202
        // 202 % 10 ? what's doesn't divide evenly into 202?
        // 20 * 10 = 200
        // 2
        // 202 % 10 = 2
        // uint256 indexOfWinner = randomWords[0] % dailyRafflePlayers.length;
        // address payable recentWinner = dailyRafflePlayers[indexOfWinner];
        // recentRaffleWinner = recentWinner;
        // // update the daily raffle winnner balance on reward contract
        // updateUsdcBonusOnRewardContract(recentRaffleWinner, dailyRaffleBalance);


        // resetUserInDailyRaffle(); // must do before resetting dailyRafflePlayers
        // dailyRafflePlayers = new address payable[](0);
        
        // lastTimeStamp = block.timestamp;


        // // transfer USDC to reward contract and reset balances
        // transferUsdcBonusesToRewardContract();

        // raffleMintState = RaffleMintState.OPEN;
        // emit WinnerPicked(recentWinner);
    }

    


    
    // THIS IS FAKE FULLFILL FUNCTION FOR TESTING ONLY, REMOVE BEFORE DEPLOYMENT
    function getRaffleWinner() public TRBC_contract_only {

        require(msg.sender == TheRanchBTCBullsCommunityAddress, "must be approved to interact");

        // dailyRafflePlayers size 10
        // randomNumber 202
        // 202 % 10 ? what's doesn't divide evenly into 202?
        // 20 * 10 = 200
        // 2
        // 202 % 10 = 2

        uint dailyRafflePlayersCount = getNumberOfRafflePlayers();

        uint256 indexOfWinner = 1231656564651654 % dailyRafflePlayersCount;

        // send indexOfWinner to the proxy contract 
        TheRanchBTCBullsCommunity TRBC = TheRanchBTCBullsCommunity(TheRanchBTCBullsCommunityAddress);
        TRBC.mintingRaffle(indexOfWinner);

        // address payable recentWinner = dailyRafflePlayers[indexOfWinner];
        // // update the daily raffle winnner balance on reward contract
    }



    function getNumberOfRafflePlayers() internal returns (uint) {
        TheRanchBTCBullsCommunity TRBC = TheRanchBTCBullsCommunity(TheRanchBTCBullsCommunityAddress);
        return TRBC.getNumberOfRafflePlayers();
    }



    function setTheRanchBTCBullsCommunityAddress(address _address) public onlyOwner {
        if (address(_address ) == address(0)) { revert Address_CantBeAddressZero();}
        TheRanchBTCBullsCommunityAddress = _address;
    }

    function setDefenderRole(address _address, bool value) external onlyOwner {
        isDefenderRole[_address] = value;
    }
    

}
