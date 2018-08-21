pragma solidity ^0.4.24;

import "https://github.com/OpenZeppelin/zeppelin-solidity/contracts/token/ERC721/ERC721Token.sol";
import "https://github.com/OpenZeppelin/zeppelin-solidity/contracts/ownership/Ownable.sol";
import "https://github.com/Arachnid/solidity-stringutils/strings.sol";
import "./PreOrder.sol";
import "./CarToken.sol";

contract CarFactory is Ownable {
    using strings for *;

    uint256 public constant MAX_CARS = 30000 + 150000 + 1000000;
    uint256 public mintedCars = 0;
    address preOrderAddress;
    CarToken token;

    mapping(uint256 => uint256) public tankSizes;
    mapping(uint256 => uint) public savedTypes;
    mapping(uint256 => bool) public giveawayCar;
    
    mapping(uint => uint256[]) public availableIds;
    mapping(uint => uint256) public idCursor;

    event CarMinted(uint256 _tokenId, string _metadata, uint cType);
    event CarSellingBeings();



    modifier onlyPreOrder {
        require(msg.sender == preOrderAddress, "Not authorized");
        _;
    }

    modifier isInitialized {
        require(preOrderAddress != address(0), "No linked preorder");
        require(address(token) != address(0), "No linked token");
        _;
    }

    function uintToString(uint v) internal pure returns (string) {
        uint maxlength = 100;
        bytes memory reversed = new bytes(maxlength);
        uint i = 0;
        while (v != 0) {
            uint remainder = v % 10;
            v = v / 10;
            reversed[i++] = byte(48 + remainder);
        }
        bytes memory s = new bytes(i); // i + 1 is inefficient
        for (uint j = 0; j < i; j++) {
            s[j] = reversed[i - j - 1]; // to avoid the off-by-one error
        }
        string memory str = string(s);  // memory isn't implicitly convertible to storage
        return str; // this was missing
    }

    function mintFor(uint cType, address newOwner) public onlyPreOrder isInitialized returns (uint256) {
        require(mintedCars < MAX_CARS, "Factory has minted the max number of cars");
        
        uint256 _tokenId = nextAvailableId(cType);
        require(!token.exists(_tokenId), "Token already exists");

        string memory id = uintToString(_tokenId).toSlice().concat(".json".toSlice());

        uint256 tankSize = tankSizes[_tokenId];
        string memory _metadata = "https://vault.warriders.com/".toSlice().concat(id.toSlice());

        token.mint(_tokenId, _metadata, cType, tankSize, newOwner);
        mintedCars++;
        
        return _tokenId;
    }

    function giveaway(uint256 _tokenId, uint256 _tankSize, uint cType, bool markCar, address dst) public onlyOwner isInitialized {
        require(dst != address(0), "No destination address given");
        require(!token.exists(_tokenId), "Token already exists");
        require(dst != owner);
        require(dst != address(this));
        require(_tankSize <= token.maxTankSizes(cType));
            
        tankSizes[_tokenId] = _tankSize;
        savedTypes[_tokenId] = cType;

        string memory id = uintToString(_tokenId).toSlice().concat(".json".toSlice());
        string memory _metadata = "https://vault.warriders.com/".toSlice().concat(id.toSlice());

        token.mint(_tokenId, _metadata, cType, _tankSize, dst);
        mintedCars++;

        giveawayCar[_tokenId] = markCar;
    }

    function setTokenMeta(uint256[] _tokenIds, uint256[] ts, uint[] cTypes) public onlyOwner isInitialized {
        for (uint i = 0; i < _tokenIds.length; i++) {
            uint256 _tokenId = _tokenIds[i];
            uint cType = cTypes[i];
            uint256 _tankSize = ts[i];

            require(_tankSize <= token.maxTankSizes(cType));
            
            tankSizes[_tokenId] = _tankSize;
            savedTypes[_tokenId] = cType;
            
            
            availableIds[cTypes[i]].push(_tokenId);
        }
    }
    
    function nextAvailableId(uint cType) private returns (uint256) {
        uint256 currentCursor = idCursor[cType];
        
        require(currentCursor < availableIds[cType].length);
        
        uint256 nextId = availableIds[cType][currentCursor];
        idCursor[cType] = currentCursor + 1;
        return nextId;
    }

    /**
    Attach the preOrder that will be receiving tokens being marked for sale by the
    sellCar function
    */
    function attachPreOrder(address dst) public onlyOwner {
        require(preOrderAddress == address(0));
        require(dst != address(0));

        //Enforce that address is indeed a preorder
        PreOrder preOrder = PreOrder(dst);

        preOrderAddress = address(preOrder);
    }

    /**
    Attach the token being used for things
    */
    function attachToken(address dst) public onlyOwner {
        require(address(token) == address(0));
        require(dst != address(0));

        //Enforce that address is indeed a preorder
        CarToken ct = CarToken(dst);

        token = ct;
    }
}
