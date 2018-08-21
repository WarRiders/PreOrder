pragma solidity ^0.4.22;

import "https://github.com/OpenZeppelin/zeppelin-solidity/contracts/token/ERC721/ERC721Receiver.sol";
import "https://github.com/OpenZeppelin/zeppelin-solidity/contracts/lifecycle/Destructible.sol";
import "./CarToken.sol";
import "./CarFactory.sol";

contract PreOrder is Destructible {
    /**
     * The current price for any given type (int)
     */
    mapping(uint => uint256) public currentTypePrice;

    // Maps Premium car variants to the tokens minted for their description
    // INPUT: variant #
    // OUTPUT: list of cars
    mapping(uint => uint256[]) public premiumCarsBought;
    mapping(uint => uint256[]) public midGradeCarsBought;
    mapping(uint => uint256[]) public regularCarsBought;
    mapping(uint256 => address) public tokenReserve;

    event consumerBulkBuy(uint256[] variants, address reserver, uint category);
    event CarBought(uint256 carId, uint256 value, address purchaser, uint category);
    event Withdrawal(uint256 amount);

    uint256 public constant COMMISSION_PERCENT = 5;

    //Max number of premium cars
    uint256 public constant MAX_PREMIUM = 30000;
    //Max number of midgrade cars
    uint256 public constant MAX_MIDGRADE = 150000;
    //Max number of regular cars
    uint256 public constant MAX_REGULAR = 1000000;

    //Max number of premium type cars
    uint public PREMIUM_TYPE_COUNT = 5;
    //Max number of midgrade type cars
    uint public MIDGRADE_TYPE_COUNT = 3;
    //Max number of regular type cars
    uint public REGULAR_TYPE_COUNT = 3;

    uint private midgrade_offset = 5;
    uint private regular_offset = 6;

    uint256 public constant GAS_REQUIREMENT = 250000;

    //Premium type id
    uint public constant PREMIUM_CATEGORY = 1;
    //Midgrade type id
    uint public constant MID_GRADE_CATEGORY = 2;
    //Regular type id
    uint public constant REGULAR_CATEGORY = 3;
    
    mapping(address => uint256) internal commissionRate;
    
    address internal constant OPENSEA = 0x5b3256965e7C3cF26E11FCAf296DfC8807C01073;

    //The percent increase for any given type
    mapping(uint => uint256) internal percentIncrease;
    mapping(uint => uint256) internal percentBase;
    //uint public constant PERCENT_INCREASE = 101;

    //How many car is in each category currently
    uint256 public premiumHold = 30000;
    uint256 public midGradeHold = 150000;
    uint256 public regularHold = 1000000;

    bool public premiumOpen = false;
    bool public midgradeOpen = false;
    bool public regularOpen = false;

    //Reference to other contracts
    CarToken public token;
    //AuctionManager public auctionManager;
    CarFactory internal factory;

    address internal escrow;

    modifier premiumIsOpen {
        //Ensure we are selling at least 1 car
        require(premiumHold > 0, "No more premium cars");
        require(premiumOpen, "Premium store not open for sale");
        _;
    }

    modifier midGradeIsOpen {
        //Ensure we are selling at least 1 car
        require(midGradeHold > 0, "No more midgrade cars");
        require(midgradeOpen, "Midgrade store not open for sale");
        _;
    }

    modifier regularIsOpen {
        //Ensure we are selling at least 1 car
        require(regularHold > 0, "No more regular cars");
        require(regularOpen, "Regular store not open for sale");
        _;
    }

    modifier onlyFactory {
        //Only factory can use this function
        require(msg.sender == address(factory), "Not authorized");
        _;
    }

    modifier onlyFactoryOrOwner {
        //Only factory or owner can use this function
        require(msg.sender == address(factory) || msg.sender == owner, "Not authorized");
        _;
    }

    function() public payable { }

    constructor(
        address tokenAddress,
        address tokenFactory,
        address e
    ) public {
        token = CarToken(tokenAddress);

        factory = CarFactory(tokenFactory);

        escrow = e;

        //Set percent increases
        percentIncrease[1] = 100008;
        percentBase[1] = 100000;
        percentIncrease[2] = 100015;
        percentBase[2] = 100000;
        percentIncrease[3] = 1002;
        percentBase[3] = 1000;
        percentIncrease[4] = 1004;
        percentBase[4] = 1000;
        percentIncrease[5] = 1012;
        percentBase[5] = 1000;
        
        commissionRate[OPENSEA] = 10;
    }
    
    function setCommission(address referral, uint256 percent) public onlyOwner {
        require(percent > COMMISSION_PERCENT);
        require(percent < 95);
        percent = percent - COMMISSION_PERCENT;
        
        commissionRate[referral] = percent;
    }
    
    function setPercentIncrease(uint256 increase, uint256 base, uint cType) public onlyOwner {
        require(increase > base);
        
        percentIncrease[cType] = increase;
        percentBase[cType] = base;
    }

    function openShop(uint category) public onlyOwner {
        require(category == 1 || category == 2 || category == 3, "Invalid category");

        if (category == PREMIUM_CATEGORY) {
            premiumOpen = true;
        } else if (category == MID_GRADE_CATEGORY) {
            midgradeOpen = true;
        } else if (category == REGULAR_CATEGORY) {
            regularOpen = true;
        }
    }

    /**
     * Set the starting price for any given type. Can only be set once, and value must be greater than 0
     */
    function setTypePrice(uint cType, uint256 price) public onlyOwner {
        if (currentTypePrice[cType] == 0) {
            require(price > 0, "Price already set");
            currentTypePrice[cType] = price;
        }
    }

    /**
    Withdraw the amount from the contract's balance. Only the contract owner can execute this function
    */
    function withdraw(uint256 amount) public onlyOwner {
        uint256 balance = address(this).balance;

        require(amount <= balance, "Requested to much");
        owner.transfer(amount);

        emit Withdrawal(amount);
    }

    function reserveManyTokens(uint[] cTypes, uint category) public payable returns (bool) {
        if (category == PREMIUM_CATEGORY) {
            require(premiumOpen, "Premium is not open for sale");
        } else if (category == MID_GRADE_CATEGORY) {
            require(midgradeOpen, "Midgrade is not open for sale");
        } else if (category == REGULAR_CATEGORY) {
            require(regularOpen, "Regular is not open for sale");
        } else {
            revert();
        }

        address reserver = msg.sender;

        uint256 ether_required = 0;
        for (uint i = 0; i < cTypes.length; i++) {
            uint cType = cTypes[i];

            uint256 price = priceFor(cType);

            ether_required += (price + GAS_REQUIREMENT);

            currentTypePrice[cType] = price;
        }

        require(msg.value >= ether_required);

        uint256 refundable = msg.value - ether_required;

        escrow.transfer(ether_required);

        if (refundable > 0) {
            reserver.transfer(refundable);
        }

        emit consumerBulkBuy(cTypes, reserver, category);
    }

     function buyBulkPremiumCar(address referal, uint[] variants, address new_owner) public payable premiumIsOpen returns (bool) {
         uint n = variants.length;
         require(n <= 10, "Max bulk buy is 10 cars");

         for (uint i = 0; i < n; i++) {
             buyCar(referal, variants[i], false, new_owner, PREMIUM_CATEGORY);
         }
     }

     function buyBulkMidGradeCar(address referal, uint[] variants, address new_owner) public payable midGradeIsOpen returns (bool) {
         uint n = variants.length;
         require(n <= 10, "Max bulk buy is 10 cars");

         for (uint i = 0; i < n; i++) {
             buyCar(referal, variants[i], false, new_owner, MID_GRADE_CATEGORY);
         }
     }

     function buyBulkRegularCar(address referal, uint[] variants, address new_owner) public payable regularIsOpen returns (bool) {
         uint n = variants.length;
         require(n <= 10, "Max bulk buy is 10 cars");

         for (uint i = 0; i < n; i++) {
             buyCar(referal, variants[i], false, new_owner, REGULAR_CATEGORY);
         }
     }

    function buyCar(address referal, uint cType, bool give_refund, address new_owner, uint category) public payable returns (bool) {
        require(category == PREMIUM_CATEGORY || category == MID_GRADE_CATEGORY || category == REGULAR_CATEGORY);
        if (category == PREMIUM_CATEGORY) {
            require(cType == 1 || cType == 2 || cType == 3 || cType == 4 || cType == 5, "Invalid car type");
            require(premiumHold > 0, "No more premium cars");
            require(premiumOpen, "Premium store not open for sale");
        } else if (category == MID_GRADE_CATEGORY) {
            require(cType == 6 || cType == 7 || cType == 8, "Invalid car type");
            require(midGradeHold > 0, "No more midgrade cars");
            require(midgradeOpen, "Midgrade store not open for sale");
        } else if (category == REGULAR_CATEGORY) {
            require(cType == 9 || cType == 10 || cType == 11, "Invalid car type");
            require(regularHold > 0, "No more regular cars");
            require(regularOpen, "Regular store not open for sale");
        }

        uint256 price = priceFor(cType);
        require(price > 0, "Price not yet set");
        require(msg.value >= price, "Not enough ether sent");
        /*if (tokenReserve[_tokenId] != address(0)) {
            require(new_owner == tokenReserve[_tokenId], "You don't have the rights to buy this token");
        }*/
        currentTypePrice[cType] = price; //Set new type price

        uint256 _tokenId = factory.mintFor(cType, new_owner); //Now mint the token
        
        if (category == PREMIUM_CATEGORY) {
            premiumCarsBought[cType].push(_tokenId);
            premiumHold--;
        } else if (category == MID_GRADE_CATEGORY) {
            midGradeCarsBought[cType - 5].push(_tokenId);
            midGradeHold--;
        } else if (category == REGULAR_CATEGORY) {
            regularCarsBought[cType - 8].push(_tokenId);
            regularHold--;
        }

        if (give_refund && msg.value > price) {
            uint256 change = msg.value - price;

            msg.sender.transfer(change);
        }

        if (referal != address(0)) {
            require(referal != msg.sender, "The referal cannot be the sender");
            require(referal != tx.origin, "The referal cannot be the tranaction origin");
            require(referal != new_owner, "The referal cannot be the new owner");

            //The commissionRate map adds any partner bonuses, or 0 if a normal user referral
            uint256 totalCommision = COMMISSION_PERCENT + commissionRate[referal];

            uint256 commision = (price * totalCommision) / 100;

            referal.transfer(commision);
        }

        emit CarBought(_tokenId, price, new_owner, category);
    }

    /**
    Get the price for any car with the given _tokenId
    */
    function priceFor(uint cType) public view returns (uint256) {
        uint256 percent = percentIncrease[cType];
        uint256 base = percentBase[cType];

        uint256 currentPrice = currentTypePrice[cType];
        uint256 nextPrice = (currentPrice * percent);

        //Return the next price, as this is the true price
        return nextPrice / base;
    }

    function sold(uint256 _tokenId) public view returns (bool) {
        return token.exists(_tokenId);
    }
}
