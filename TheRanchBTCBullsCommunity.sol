// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;


import "@UPGopenzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@UPGopenzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@UPGopenzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@UPGopenzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@UPGopenzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@UPGopenzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@UPGopenzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@UPGopenzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@UPGopenzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";

import "./TheRanchBTCBullsChainLinkVRF.sol";


error Minting_ExceedsTotalBulls();
error Minting_ExceedsMintingLimitPerAddress();
error Minting_PublicSaleNotLive();
error Minting_IsZeroOrBiggerThanFive();
error Contract_CurrentlyPaused_CheckSocials();
error Contract_CurrentlyDoingMintRaffle();
error Pause_MustSetAllVariablesFirst();
error Pause_BaseURIMustBeSetFirst();
error Pause_MustBePaused();
error Rewarding_NotReady();
error Rewarding_SkippingOrDoubleRewarding();
error Rewarding_HasAlreadyHappenedThisMonth();
error Rewarding_SatoshiRoundingErrorWillHappen();
error Maintenance_UpdatingNotReady();
error Maintenance_NoMaintenanceFeesRequired();
error Liquidation_NothingToDo();
error BadLogicInputParameter();
error Partner_NotAllowed();
error Address_CantBeAddressZero();
error Blacklisted();
error Rewarding_NoBalanceToWithdraw();




/// @custom:security-contact defibulls@gmail.com
contract TheRanchBTCBullsCommunity is 
    Initializable,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC2981Upgradeable
    {

    using StringsUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private _tokenSupply;   

    // token information 
    address public wbtcTokenContract; 
    address public usdcTokenContract; 
    uint public wbtcTokenDecimals;     
    uint public usdcTokenDecimals;     

    // coreTeam Addresses
    address public coreTeam_1;
    address public coreTeam_2;

    //gnosis-safe address 
    address public hostingSafe;
    address public btcMinersSafe;

    // Minting 
    uint public constant maxSupply = 10000;
    uint256 public constant mintingCost = 350;  // USDC.e
    uint256 public nftPerAddressLimit;
    mapping(address => uint256) public addressMintCount; // how many times has this address minted an NFT from this contract. 

    bool public publicSaleLive;
    bool public paused;
    bool public raffleLive;

    mapping(address => bool) public isBlacklisted;

    mapping(address => bool) public userInDailyRaffle;  // Is the person already in the daily raffle?

    mapping(address => address) public myPartner;   // partner mapping; msg.sender  ==> who referred them
    mapping(address => uint256) public myParnterNetworkTeamCount;   // Keeps track of how many people are currently using an address as their partner 

    // Contract Balances
    uint256 public btcMinersSafeBalance;
    uint256 public hostingSafeBalance;     // reserve kept for hosting fees and will be used if people don't pay their maintenance fees on time
    uint256 public USDCRewardsBalance;    // amount held within contract for referrals and raffle balance 
    uint256 public dailyRaffleBalance;    // Strictly the Raffle amount of USDC to be award on the raffle 



    // NFT INFO 
    string private baseURI;
    string private baseExtension;
 
 
    // Raffle Variables
    address[] private dailyRafflePlayers;
 
    // Maintenance Fees Variables and Mappings
    // The amount calculated for hosting invoice / NFT count 
    uint256 public calculatedMonthlyMaintenanceFee;   


    /**
     * @dev For addresses that are more than 3 months behind on the maintenance fees, each 
     * each address added here will get liquidated
    */
    address[] internal upForLiquidation; 

    // Stockyard allows the rewardBulls function to be more modular. 
    struct StockyardInfo {
        uint startingIndex;
        uint endingIndex;
    }

    mapping (uint => StockyardInfo) public stockyardInfo;

 

    // BTC Bull Owners information 
    struct BTCBullOwner {
        uint256 USDC_Balance;
        uint256 WBTC_Balance;
        uint256 maintenanceFeeBalance;    
        uint maintenanceFeesStanding;     // how many months are they behind on the maintenance fees? 0 means all paid up, 4 gets liquidated.
        uint lastRewardDate;        // this tracks when the last time I rewarded them. Aug 2022 would be 0822, Mar 2023 would be 0323. 
    }

    mapping(address => BTCBullOwner) public btcBullOwners;


    // Monthly WBTC rewarding variables 
    uint public currentRewardingDate;        // This date is set when we send WBTC into the contract to reward the BTC Bulls to confirm who has been paid out. 
    uint public stockyardsThatHaveBeenRewardedCount;  // security check to make sure we don't rewarding the same stockyard twice or skip a stockyard
    uint256 public payPerNftForTheMonth;      // Total Monday WBTC deposit / totalSupply()
    uint256 public lastDeposit;         // variable that tracks last deposit. If not reset after rewarding, it keeps serves as a check to deposit money and start rewarding
    address[] public rewardedAddresses;  // array for address if we have EVER rewarded them. 
    bool public readyToReward;   // bool to confirm we have met all the requirements and are good to go to call the rewardBulls function 


    /**
     * @dev The isEcosystemRole is for other contracts that are allowed to update the USDC for BTC BULL Owners on this contract.
     * @dev The isDefenderRole our openzeppelin Defender account working with autotasks and sentinals.
     * @dev The isChainLinkVRFRole our chainlink VRF contract that does the minting raffle for this contract.
    */
    mapping(address => bool) public isEcosystemRole;
    mapping(address => bool) public isDefenderRole;
    address public ChainLinkVRFContract;         
 

    modifier ADMIN_OR_DEFENDER {
        require(msg.sender == owner() || isDefenderRole[msg.sender] == true, "Caller is not an OWNER OR DEFENDER");
        _;
    }

   
    event PauseChanged(address _account, bool _changedTo);

    event NewBullsEnteringRanch(
        address indexed NewbullOwner,
        bool indexed RaffleEntered,
        uint256  BullsPurchased,
        uint256 _NFTCount
    );

    event mintingRaffleEvent(
        uint256 indexed winningIndex,
        address indexed raffleWinner,
        uint256  raffleWinAmount

    );
    
    event withdrawUSDCBalanceForAddressEvent(
        address indexed nftOwner,
        uint256 indexed totalAmountTransferred
    );

    event withdrawWbtcBalanceEvent(
        address indexed nftOwner,
        uint256 indexed totalAmountTransferred  
    );

    event liquidationEvent (
        address indexed nftOwner,
        uint256 indexed totalAmountliquidated
    );

    event rewardEvent(
            uint256 payPerNftForTheMonth,
            uint256 maintenanceFeesForEachNFT,
            uint indexed startingIndex,
            uint indexed endingIndex
    );

    event resetRewardEvent(
        address caller,
        string sectionMessage
    );

     event setPayPerNFTEvent(
        uint256 totalDeposit,
        uint256 calculatedPayPerNFT,
        uint rewardDate
    );


    event payMaintanenceFeesEvent(
            address indexed nftOwner,
            uint256 indexed totalAmountPayedWithCurrentRewards,
            uint256 indexed totalAmountPayedWithoutCurrentRewards
    );


    function initialize() public initializer {
        __ERC721_init("TheRanch_BTC_Bulls_Community", "TRBC");
        __ERC721Enumerable_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        nftPerAddressLimit = 50;
        wbtcTokenDecimals = 8;
        usdcTokenDecimals = 6;
        publicSaleLive = false;
        paused = true;
        baseExtension = ".json";    
    }


    function approveToken(uint256 _tokenamount)public returns (bool) {
        IERC20Upgradeable usdcToken = IERC20Upgradeable(usdcTokenContract);
        usdcToken.approve(address(this), _tokenamount); 
        return true;
    }

   // MINTING
    /**
     * @dev This is the function does the following things:
     * 0. Only works if not paused
     * 1. Allows users to mint new NFTs 1 - 10 per tx 
     * 2. Updates Mapping for their total count of mints
     * 3. Uses a referral/partners system to see who gets the referral bonus.
     * 4. Enters user into the daily raffle if they chose to do so. 
     * 5. If msg.sender elects to enter raffle, 95% goes to btcMinersFund, if they do not, 98% does. 
    */
    function mint(uint256 _tokenQuantity, bool _enterRaffle) public payable {
        if (paused) { revert Contract_CurrentlyPaused_CheckSocials();}
        if (raffleLive) { revert Contract_CurrentlyDoingMintRaffle();}
        if (!publicSaleLive) { revert Minting_PublicSaleNotLive();}
        if (_tokenQuantity ==  0 || _tokenQuantity > 5) { revert Minting_IsZeroOrBiggerThanFive();}
        if (_tokenSupply.current() + _tokenQuantity > maxSupply) {revert Minting_ExceedsTotalBulls();}
        if (addressMintCount[msg.sender] + _tokenQuantity > nftPerAddressLimit) { revert Minting_ExceedsMintingLimitPerAddress();}


        IERC20Upgradeable usdcToken = IERC20Upgradeable(usdcTokenContract);
        uint256 minting_cost_per_bull = mintingCost * 10 ** usdcTokenDecimals;
        uint256 totalTransactionCost = minting_cost_per_bull * _tokenQuantity;
        usdcToken.safeTransferFrom(msg.sender, address(this), (totalTransactionCost));

        for(uint256 i = 0; i < _tokenQuantity; i++) {
            _tokenSupply.increment();
            addressMintCount[msg.sender] += 1;
            _safeMint(msg.sender, _tokenSupply.current());
        }

        // Voluntary Raffle entry allow users to enter raffle is they choose too with _enterRaffle == True
        uint256 raffleFundAmt; 

        if (_enterRaffle == true){
            raffleFundAmt = totalTransactionCost * 3 / 100;
            if (getUserAlreadyInDailyRaffleStatus(msg.sender) == false){
                dailyRafflePlayers.push(payable(msg.sender));
                userInDailyRaffle[msg.sender] = true; 
            }
            dailyRaffleBalance += raffleFundAmt;
        } else {
            raffleFundAmt = 0;
        }

        // update contract balances
        uint256 referralFundAmt = totalTransactionCost * 2 / 100;
        uint256 hostingSafeAmt = totalTransactionCost * 5 / 100;
        uint256 btcMinersSafeAmt = totalTransactionCost - (referralFundAmt + raffleFundAmt)  - hostingSafeAmt; 
        USDCRewardsBalance += (referralFundAmt + raffleFundAmt);
        btcMinersSafeBalance += btcMinersSafeAmt;
        hostingSafeBalance += hostingSafeAmt; 
        
        // update USDC Reward Balances for referrals
        address referrer = myPartner[msg.sender];
        if(referrer != address(0) &&  balanceOf(referrer) > 0){
            //updateUsdcBonus(referrer, referralFundAmt);
            btcBullOwners[referrer].USDC_Balance += referralFundAmt;
        }
        else
        {
            uint256 splitReferralAmt = referralFundAmt * 50 / 100;
            // updateUsdcBonus(coreTeam_1, splitReferralAmt);
            // updateUsdcBonus(coreTeam_2, splitReferralAmt);
            btcBullOwners[coreTeam_1].USDC_Balance += splitReferralAmt;
            btcBullOwners[coreTeam_2].USDC_Balance += splitReferralAmt;
        }
        
        emit NewBullsEnteringRanch(msg.sender,_enterRaffle, _tokenQuantity, _tokenSupply.current());

        // if raffle length is at 100 entries or all bulls are minted, the raffle shall commence 
        if (dailyRafflePlayers.length == 100  || _tokenSupply.current() == 10000) {
            startRaffle();
        }
    }



    /** 
    * @dev Gets called by minting function when dailyRafflePlayers.length is at or greater than 100 or all BTC bulls are minted
      calls the chainlinkVRFContact which generates a random number and then that contracts calls this contract giving the winning
      number back. 
    
    */
    function startRaffle() internal {
        raffleLive = true;
      
        TheRanchBTCBullsChainLinkVRF CHAINLINKVRF = TheRanchBTCBullsChainLinkVRF(ChainLinkVRFContract);
        CHAINLINKVRF.getRaffleWinner();

    }




    /**
     * @dev This is the function is called from another contract in our ecoystem using Chainlink VRF V2
     * This contract must have the ChainlinkVRF role or it will revert. It calls and fullfills the request 
     * on the other contract then sends that number to this contract to award the winner. 
     * Did this approach as a workaround to use upgradeble contracts from open-zeppelin as the chainlink contracts were not compatiable. 
     */

    function mintingRaffle(uint _winningIndex) external {

        require(msg.sender == ChainLinkVRFContract, "must be the chainlinkVRF contract to interact");


        address dailyRaffleWinner = dailyRafflePlayers[_winningIndex];
        uint256 raffleWinningAmount = dailyRaffleBalance; 
        
        // update the daily raffle winnners USDC balance
        btcBullOwners[dailyRaffleWinner].USDC_Balance += dailyRaffleBalance;

        resetUserInDailyRaffle(); // must do before resetting dailyRafflePlayers
        dailyRaffleBalance = 0;  // reset dailyRaffleBalance back to zero after drawing
        dailyRafflePlayers = new address[](0);

        emit mintingRaffleEvent(_winningIndex, dailyRaffleWinner, raffleWinningAmount);
        
        raffleLive = false;
    }

   

    /**
     * @dev Once the raffle winner is picked, we loop through the dailyRafflePlayers
     * and set their booling value back to false so they can enter another raffle 
     * if they choose to mint more NFTs later on a different day.
     */
    function resetUserInDailyRaffle() internal {
        for (uint i=0; i< dailyRafflePlayers.length ; i++){
            userInDailyRaffle[dailyRafflePlayers[i]] = false;
        }
    }





    /** 
    * @dev this function is called by the multisig after we do the monthy funding of the NFTs by depostiing money into the contract
    *  and setting the Maintenance Fee for the invoice from the hosting facility. The reward function can't be called until this evaulates as true. 
    */
    function setReadyToReward() external ADMIN_OR_DEFENDER {
        if (calculatedMonthlyMaintenanceFee == 0) { revert Rewarding_NotReady();}
        if (payPerNftForTheMonth == 0) { revert Rewarding_NotReady();}

        readyToReward = true;
    }



    /** 
    * @dev This resets the monthly variables to make sure we the order of calls works correctly the next time we do it. 
    */
    function resetReadyToRewardChecks() external ADMIN_OR_DEFENDER {
        readyToReward = false;
        payPerNftForTheMonth = 0;
        calculatedMonthlyMaintenanceFee = 0;
        stockyardsThatHaveBeenRewardedCount = 0;
        lastDeposit = 0;
        emit resetRewardEvent(msg.sender, "Reset Rewarding Variables");
    }




    // This needs to be done in a single transaction. The problem is that if we try this in multiple transactions, this
    // would end up re-updating the payPerNftForTheMonth and the total payout to each NFT owner would be messed up. 
    // The only way to deposit more money into this function and update the payPerNftForTheMonth variable would be to run
    // through the rewarding, which then sets the lastDeposit back to zero and doing another round of rewarding for the month.

    function setPayPerNftForTheMonthAndCurrentRewardingDate(uint256 _totalAmountToDeposit, uint _dateOfRewarding) public onlyOwner {
        if (lastDeposit != 0) { revert Rewarding_HasAlreadyHappenedThisMonth();}
        if (_totalAmountToDeposit < 1200000) { revert Rewarding_SatoshiRoundingErrorWillHappen();}

        IERC20Upgradeable tokenContract = IERC20Upgradeable(wbtcTokenContract);
        tokenContract.safeTransferFrom(msg.sender, address(this), _totalAmountToDeposit);
        
        currentRewardingDate = _dateOfRewarding;
        lastDeposit = _totalAmountToDeposit;

        
        // in this function, lets pay out the core team first and then the 90% left gets divided up. 
        uint256 coreTeam_1_amt = _totalAmountToDeposit * 8 / 100;
        uint256 coreTeam_2_amt = _totalAmountToDeposit * 2 / 100;

        uint256 _disperableAmount = (_totalAmountToDeposit * 90 / 100); 
        uint256 payout_per_nft = _disperableAmount / _tokenSupply.current();
        payPerNftForTheMonth = payout_per_nft;

        btcBullOwners[coreTeam_1].WBTC_Balance += coreTeam_1_amt;
        btcBullOwners[coreTeam_2].WBTC_Balance += coreTeam_2_amt;

        // emit event 
        emit setPayPerNFTEvent(_totalAmountToDeposit, payout_per_nft, _dateOfRewarding);
        

    }   


    /** 
    * @dev  check all addresses who have been rewarded. If there lastRewardYearMonth isn't the currentRewardingDate, then lets investigate. If they have a WBTC balance, then we need
    * to update there maintenanceFeesStanding by 1 and add to liquidation list if they reach 4 in that category 
    */
    function updateMaintenanceStanding() external ADMIN_OR_DEFENDER {
        for( uint i; i < rewardedAddresses.length; i++) {
            address _wallet = rewardedAddresses[i];
            if (btcBullOwners[_wallet].WBTC_Balance > 0){
                if (btcBullOwners[_wallet].lastRewardDate != currentRewardingDate) {

                    // take action and add one to maintenanceFeesStanding
                    btcBullOwners[_wallet].maintenanceFeesStanding += 1;

                    if (btcBullOwners[_wallet].maintenanceFeesStanding == 4){
                        upForLiquidation.push(_wallet);
                    }
                }
            }
        }
    }


     /**
    * @dev The Reward function is a modular setup so we can go through all the NFTs in multiple passes to circumvent gas problems. 
    * 1. Only works if the readyToReward varible is true, that means all the admin tasks before rewarding have taken place.  
    * 2. updates the stockyardsThatHaveBeenRewardedCount variable to make sure we can't call the reward on the same stockyard multiple times. 
    * 3. checks the currentRewardDate for the owner's account, only lets them pass throught he function is its differnt than the current date. this allows for a single pass for that wallet and skips if they own more than one.
    * 4. Checks to see if we have every rewarded them by detecting is there lastRewardDate is not initialized yet. 
    * 5. updates the lastRewardDate for the account
    * 6. rewards user for all the NFTs the currently own on the contract. 
    * 7. updates WBTC balance for the user and a percentage is sent to their parnters account if thats set, to the core team if partner is not set. 
    * 8. updates the maintenance Fee balance that the user owes for the months (hosting fees at the mining facility)
    * 9. updates the maintenanceFeesStanding for the user, if this number is 4 then they are up for liquidation and pushed to that array to be in queue for liquidating them
    * 10. emits event showing how much we paid for each NFT, how much the maintenance fee for each NFT was, the starting index and ending index we rewarded during the function. 
    */

    function rewardBulls(uint _stockyardNumber) public ADMIN_OR_DEFENDER {
   
        if (readyToReward == false) { revert Rewarding_NotReady();}
        if (!paused) { revert Pause_MustBePaused();}
        if (_stockyardNumber != stockyardsThatHaveBeenRewardedCount + 1) { revert Rewarding_SkippingOrDoubleRewarding();}

        stockyardsThatHaveBeenRewardedCount++ ;

        uint startingIndex = stockyardInfo[_stockyardNumber].startingIndex;
        uint endingIndex = stockyardInfo[_stockyardNumber].endingIndex;

        for( uint i = startingIndex; i <= endingIndex; i++) {
            address bullOwnerAddress = ownerOf(i);
            
            if (bullOwnerAddress != address(0)){

                // have we checked them this month, if lastRewardDate == currentRewardingDate then skip them  
                if (btcBullOwners[bullOwnerAddress].lastRewardDate != currentRewardingDate) {


                    // Have we ever rewarded them before, if not, add them into the rewarded address array. 
                    if (btcBullOwners[bullOwnerAddress].lastRewardDate == 0) {
                        rewardedAddresses.push(bullOwnerAddress);
                    }

                    BTCBullOwner storage _bullOwner = btcBullOwners[bullOwnerAddress];

                    // update lastRewardDate for this address 
                    _bullOwner.lastRewardDate = currentRewardingDate;
        

                    // get the amount of NFTs this address owns
                    uint _nftCount = walletOfOwner(bullOwnerAddress).length;

                    // get the total payout amound
                    uint256 totalPayoutForTheBullOwner = _nftCount * payPerNftForTheMonth;
                    
                    // get the referr and the referral amount 
                    address referrer = myPartner[bullOwnerAddress];
                    uint256 referralAmt = totalPayoutForTheBullOwner * 1 / 100;

                    // update the wbtc balances accordingly with their partner 
                    if(referrer != address(0) &&  balanceOf(referrer) > 0){
                        btcBullOwners[referrer].WBTC_Balance += referralAmt;
                        _bullOwner.WBTC_Balance += (totalPayoutForTheBullOwner - referralAmt);
      
    
                    } else {
                        btcBullOwners[coreTeam_1].WBTC_Balance += referralAmt;
                        btcBullOwners[coreTeam_2].WBTC_Balance += referralAmt;
                        _bullOwner.WBTC_Balance += (totalPayoutForTheBullOwner - (referralAmt * 2));
                    }

                    //  update the maintenance Fees due from the _bullOwner
                    _bullOwner.maintenanceFeeBalance += (_nftCount * calculatedMonthlyMaintenanceFee);
         

                    // update the maintenanceFeesStanding for the _bullOwner
                    _bullOwner.maintenanceFeesStanding += 1;


                    // Check if _bullOwner is more than 3 months behind on the account 
                    if (_bullOwner.maintenanceFeesStanding == 4){
                        upForLiquidation.push(bullOwnerAddress);
                    }
                }
            }
        }

        emit rewardEvent(payPerNftForTheMonth, calculatedMonthlyMaintenanceFee, startingIndex, endingIndex);
    }



    /**
    * @dev When any other contract in our ecosystem checks the owner of the BTC Bulls, it will update the USDC amount for the 
    * BTC Bulls owner on this contract. It incentives ownership of both NFTS this way: 
    * In this example, lets assume we have a HayBale NFT on another smart contract, 
    * --------------------------------------------------------------------------------------------------------------------------------------------------------
    * - own bull with and have an active partner: 96 / 4
    * - else: 96 / 2 / 2


  
    */
    function updateUsdcBonusFromAnotherContract(address[] memory _ownersOfTheNFTs, uint256 _amountToAdd) payable external {
        require(isEcosystemRole[msg.sender] == true, "must be approved to interact");

       require(msg.value == 0, "funds do not add up");

        IERC20Upgradeable usdcToken = IERC20Upgradeable(usdcTokenContract);
        usdcToken.safeTransferFrom(msg.sender,address(this), (_ownersOfTheNFTs.length * _amountToAdd ));


        for( uint i; i < _ownersOfTheNFTs.length; i++) {
            address _ownerOfNFT = _ownersOfTheNFTs[i];

        
            // get the referrer of this particular BTC Bull owner  
            address referrer = myPartner[_ownerOfNFT];
            uint256 referralAmt = _amountToAdd * 2 / 100;

            // update the usdc  balances accordingly with their partner 
            if(referrer != address(0) &&  balanceOf(referrer) > 0 && balanceOf(_ownerOfNFT) > 0){
                btcBullOwners[referrer].USDC_Balance += (referralAmt * 2);
                btcBullOwners[_ownerOfNFT].USDC_Balance += (_amountToAdd - (referralAmt * 2));
            } else {
                btcBullOwners[coreTeam_1].USDC_Balance += referralAmt;
                btcBullOwners[coreTeam_2].USDC_Balance += referralAmt;
                btcBullOwners[_ownerOfNFT].USDC_Balance += (_amountToAdd - (referralAmt * 2));
            }
        }
    }



    function getLiquidatedArrayLength() public view ADMIN_OR_DEFENDER returns (uint) {
        return upForLiquidation.length;
    }

    /**
     * @dev If the user has been added to the liquidityArray, that means they are 4 months behind on paying their maintenance fees
     * Liquidating them means transfering the WBTC out of their account and sending it the Hosting Safe Multisig wallet. 
    **/
    function liquidateOutstandingAccounts() external ADMIN_OR_DEFENDER {
        if (!paused) { revert Maintenance_UpdatingNotReady();}
        if (upForLiquidation.length < 1) { revert Liquidation_NothingToDo();}

        uint256 totalAmountLiquidated; 

        for( uint i; i < upForLiquidation.length; i++) {
            address _culprit = upForLiquidation[i];
            uint256 _amount = btcBullOwners[_culprit].WBTC_Balance;
            btcBullOwners[_culprit].WBTC_Balance = 0;
            totalAmountLiquidated += _amount; 

            // reset fees and months behind. 
            btcBullOwners[_culprit].maintenanceFeeBalance = 0;
            btcBullOwners[_culprit].maintenanceFeesStanding = 0;
            
            // emit event
            emit liquidationEvent(_culprit, _amount) ;
            
        }

        upForLiquidation = new address[](0);

        IERC20Upgradeable tokenContract = IERC20Upgradeable(wbtcTokenContract);
        tokenContract.approve(address(this), totalAmountLiquidated);
        tokenContract.safeTransferFrom(address(this), hostingSafe, totalAmountLiquidated);
    }


    /**
     * @dev If the user has USDC rewards to within their account
     * the maintanence fee balance will be deducted from that. 
     * If it doesn't cover the entire maintenance fee cost, 
     * the rest of the amount will be asked to beapproved and sent to the contract. 
    **/
    function payMaintanenceFees() external nonReentrant {

        uint256 _feesDue = btcBullOwners[msg.sender].maintenanceFeeBalance;
        uint256 _balance = btcBullOwners[msg.sender].USDC_Balance;
        
        if (_feesDue == 0) { revert Maintenance_NoMaintenanceFeesRequired();}

        if (_balance >= _feesDue){

            btcBullOwners[msg.sender].USDC_Balance -= _feesDue;
            hostingSafeBalance += _feesDue; 

            emit payMaintanenceFeesEvent(msg.sender, _feesDue, 0);
        } else {

            uint256 amt_needed =  _feesDue - _balance;
            if(_balance == 0){
                IERC20Upgradeable usdcToken = IERC20Upgradeable(usdcTokenContract);
                usdcToken.safeTransferFrom(msg.sender, address(this), (_feesDue));
                hostingSafeBalance += _feesDue; 
            } else {
                
                btcBullOwners[msg.sender].USDC_Balance -= _balance; 

                IERC20Upgradeable usdcToken = IERC20Upgradeable(usdcTokenContract);
                usdcToken.safeTransferFrom(msg.sender, address(this), (amt_needed));

                hostingSafeBalance += (amt_needed + _balance); 
            }

            emit payMaintanenceFeesEvent(msg.sender, _balance, amt_needed);
        }

        // reset fees and months behind. 
        btcBullOwners[msg.sender].maintenanceFeeBalance = 0;
        btcBullOwners[msg.sender].maintenanceFeesStanding = 0;

    }


    function setPartnerAddress(address _newPartner)  public {
        if (address(_newPartner) == address(0)) { revert Partner_NotAllowed();}
        if (address(_newPartner) == msg.sender) { revert Partner_NotAllowed();}

        address currentPartner = myPartner[msg.sender];
    
        if (currentPartner == address(0)){
            myPartner[msg.sender] = _newPartner;
            myParnterNetworkTeamCount[_newPartner] += 1;
        } else {
            myPartner[msg.sender] = _newPartner;
            myParnterNetworkTeamCount[currentPartner] -= 1;
            myParnterNetworkTeamCount[_newPartner] += 1;
        }
    }

    // Contract Funding / Withdrawing / Transferring
    function fund() public payable {}


    function withdrawNativeToken() external onlyOwner {
        (bool sent, bytes memory data) = msg.sender.call{value: address(this).balance}("");
        require(sent, "Failed to send Native Token");
    }

    function withdrawToken(address _tokenContract) external onlyOwner {
        IERC20Upgradeable tokenContract = IERC20Upgradeable(_tokenContract);
        uint256 _amt;
        if (_tokenContract == usdcTokenContract){
            _amt = tokenContract.balanceOf(address(this)) - (btcMinersSafeBalance + hostingSafeBalance + USDCRewardsBalance);
        } else if (_tokenContract == wbtcTokenContract){
            _amt = btcBullOwners[msg.sender].WBTC_Balance; 
        } else {
            _amt = tokenContract.balanceOf(address(this));
        }
        tokenContract.safeTransfer(msg.sender, _amt);
    }

    function withdrawBtcMinersSafeBalance() external ADMIN_OR_DEFENDER {
        IERC20Upgradeable tokenContract = IERC20Upgradeable(usdcTokenContract);
        uint256 amtToTransfer = btcMinersSafeBalance;
        tokenContract.approve(address(this), amtToTransfer);
        tokenContract.safeTransferFrom(address(this), btcMinersSafe, amtToTransfer);
        btcMinersSafeBalance -= amtToTransfer;

    
    }

    function withdrawHostingSafeBalance() external ADMIN_OR_DEFENDER {
        IERC20Upgradeable tokenContract = IERC20Upgradeable(usdcTokenContract);
        uint256 amtToTransfer = hostingSafeBalance;
        tokenContract.approve(address(this), amtToTransfer);
        tokenContract.safeTransferFrom(address(this), hostingSafe, amtToTransfer);
        hostingSafeBalance -= amtToTransfer;
    }


    function withdrawWbtcBalance() external nonReentrant {
        if (paused) { revert Contract_CurrentlyPaused_CheckSocials();}
        if (isBlacklisted[msg.sender]) { revert Blacklisted();}

        require(btcBullOwners[msg.sender].maintenanceFeeBalance == 0, "You must pay maintenance fee balance before WBTC withdrawal is allowed");

        // Get the total Balance to award the owner of the NFT(s)
        uint256 myBalance = btcBullOwners[msg.sender].WBTC_Balance; 
        if (myBalance == 0) { revert Rewarding_NoBalanceToWithdraw();}

        // Transfer Balance 
        IERC20Upgradeable(wbtcTokenContract).safeTransfer(msg.sender, myBalance );

        // update wbtc balance for nft owner
        btcBullOwners[msg.sender].WBTC_Balance = 0;
        
        emit withdrawWbtcBalanceEvent(msg.sender, myBalance);
    }

    function withdrawUsdcBalance() external nonReentrant {
        if (paused) { revert Contract_CurrentlyPaused_CheckSocials();}
        if (isBlacklisted[msg.sender]) { revert Blacklisted();}
        
        // Get USDC rewards balance for msg.sender
        uint256 myBalance = btcBullOwners[msg.sender].USDC_Balance;
        if (myBalance == 0) { revert Rewarding_NoBalanceToWithdraw();}
 
        // Transfer Balance 
        IERC20Upgradeable(usdcTokenContract).safeTransfer(msg.sender, (myBalance));
        // update mapping on contract 

        btcBullOwners[msg.sender].USDC_Balance = 0  ;
        
        // update USDC Rewards Balance Total
        USDCRewardsBalance -= myBalance;
        
        // emit event
        emit withdrawUSDCBalanceForAddressEvent(msg.sender, myBalance);
        
    }

    /** Getter Functions */

    /**
     * @dev returns how many people have ever been rewarded from owning a BTC Bull
     */
    function getRewardAddressesLength() public view returns (uint){
        return rewardedAddresses.length;
    }

    function getMaintenanceFeeBalanceForAddress() public view returns (uint256){
        return btcBullOwners[msg.sender].maintenanceFeeBalance;
    }

    function getMaintenanceFeeStandingForAddress() public view returns (uint){
        return btcBullOwners[msg.sender].maintenanceFeesStanding;
    }


    function getWbtcBalanceForAddress() public view returns (uint256){
        return btcBullOwners[msg.sender].WBTC_Balance;
    }


    function getUsdcBalanceForAddress() public view returns (uint256) {
        return btcBullOwners[msg.sender].USDC_Balance;
    }

    /**
     * @dev returns how many people are using them as someone as their partner
     */
    function getPartnerNetworkTeamCount() public view returns (uint) {
        return myParnterNetworkTeamCount[msg.sender];
    }

    /**
     * @dev checks if an address is using them as their partner.
     */
    function getAreTheyOnMyPartnerNetworkTeam(address _adressToCheck) public view returns (bool) {
        if (myPartner[_adressToCheck] == msg.sender){
            return true;
        }
        return false;
    }


    function getUserAlreadyInDailyRaffleStatus(address _address) public view returns (bool) {
        return userInDailyRaffle[_address];
    }

    function walletOfOwner(address _owner) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }


    function getNumberOfRafflePlayers() public view returns (uint256) {
        return dailyRafflePlayers.length;
    }   

    function getBlacklistedStatus(address _address) public view returns (bool) {
        return isBlacklisted[_address];
    }

   // METADATA
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId),"ERC721Metadata: URI query for nonexistent token");
        string memory currentBaseURI = _baseURI();
        return bytes(currentBaseURI).length > 0 ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension)) : "";
    }

    // ERC165
    function supportsInterface(bytes4 interfaceId) public view override(ERC721EnumerableUpgradeable, IERC165Upgradeable) returns (bool) {
        return interfaceId == type(IERC2981Upgradeable).interfaceId || super.supportsInterface(interfaceId);
    }

    // IERC2981
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) external view override returns (address, uint256 royaltyAmount) {
        _tokenId; // silence solc warning
        royaltyAmount = _salePrice * 5 / 100;  // 5%
        return (coreTeam_1, royaltyAmount);
    }


    // Contract Control _ ADMIN ONLY
    function setBaseURI(string memory _newBaseURI) public onlyOwner{
        baseURI = _newBaseURI;
    }

    function setBaseExtension(string memory _newBaseExtension) external onlyOwner {
        baseExtension = _newBaseExtension;
    }

    function togglePublicSaleStatus() external onlyOwner{
        publicSaleLive = !publicSaleLive;
    }

    function setPauseStatus(bool _paused) external ADMIN_OR_DEFENDER{
        if(address(coreTeam_1) == address(0)) { revert Pause_MustSetAllVariablesFirst();}
        if(address(coreTeam_2) == address(0)) { revert Pause_MustSetAllVariablesFirst();}
        if(address(usdcTokenContract) == address(0)) { revert Pause_MustSetAllVariablesFirst();}
        if(address(wbtcTokenContract) == address(0)) { revert Pause_MustSetAllVariablesFirst();}
        if(address(hostingSafe) == address(0)) { revert Pause_MustSetAllVariablesFirst();}
        if(address(btcMinersSafe) == address(0)) { revert Pause_MustSetAllVariablesFirst();}
        string memory currentBaseURI = _baseURI();
        if(bytes(currentBaseURI).length == 0) { revert Pause_BaseURIMustBeSetFirst();}

        paused = _paused;

        emit PauseChanged(msg.sender, _paused);
    }

    function setCoreTeamAddresses(address _coreTeam_1, address _coreTeam_2) external onlyOwner {
        if (address(_coreTeam_1 ) == address(0) || address(_coreTeam_2 ) == address(0)) { revert Address_CantBeAddressZero();}
        coreTeam_1 = _coreTeam_1;
        coreTeam_2 = _coreTeam_2;
    }

    function setSafeAddresses(address _hostingSafe, address _btcMinersSafe) external onlyOwner {
        if (address(_hostingSafe ) == address(0) || address(_btcMinersSafe ) == address(0)) { revert Address_CantBeAddressZero();}
        hostingSafe = _hostingSafe;
        btcMinersSafe = _btcMinersSafe;
    }

    function setUsdcTokenAddress(address _address) public onlyOwner {
        if (address(_address ) == address(0)) { revert Address_CantBeAddressZero();}
        usdcTokenContract = _address;
    }

    function setUsdcTokenDecimals(uint _decimals) public  onlyOwner {
        usdcTokenDecimals = _decimals;
    }

    function setWbtcTokenAddress(address _address) public onlyOwner {
        if (address(_address ) == address(0)) { revert Address_CantBeAddressZero();}
        wbtcTokenContract = _address;
    }

    function setWbtcTokenDecimals(uint _decimals) public onlyOwner {
        wbtcTokenDecimals = _decimals;
    }

    function blacklistMalicious(address _address, bool value) external onlyOwner {
        isBlacklisted[_address] = value;
    }

    function setEcosystemRole(address _address, bool value) external onlyOwner {
        isEcosystemRole[_address] = value;
    }

    function setDefenderRole(address _address, bool value) external onlyOwner {
        isDefenderRole[_address] = value;
    }

    function setChainlinkVrfContractAddress(address _address) external onlyOwner {
        ChainLinkVRFContract = _address;
    }

    function setMonthlyMaintenanceFeePerNFT(uint256 _monthly_maint_fee_per_nft) external onlyOwner {
        calculatedMonthlyMaintenanceFee = _monthly_maint_fee_per_nft;
    }

    function setStockYardInfo(uint _stockyardNumber, uint _startingIndex, uint _endingIndex) public onlyOwner {
        if (_startingIndex == 0 || _endingIndex == 0 || _stockyardNumber == 0) { revert BadLogicInputParameter();}
        if (_endingIndex > _tokenSupply.current()) { revert BadLogicInputParameter();}
        if (stockyardInfo[_stockyardNumber - 1].endingIndex + 1 != _startingIndex ) { revert BadLogicInputParameter();}
   
        stockyardInfo[_stockyardNumber] =  StockyardInfo(_startingIndex, _endingIndex);
    }


    function renounceOwnership() public virtual override onlyOwner {
        // do nothing
    }




}

