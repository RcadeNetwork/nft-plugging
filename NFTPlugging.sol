// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract NFTPlugging is
    Initializable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // Events
    event Plugged(
        address indexed user,
        address indexed collection,
        uint256[] tokenIds,
        uint256 pluggedAt,
        uint256 pluggedUntil
    );
    event Unplugged(
        address indexed user,
        address indexed collection,
        uint256[] tokenIds,
        uint256 unpluggedAt
    );
    event TreasuryAddressUpdated(
        address indexed oldTreasury,
        address indexed newTreasury,
        uint256 timestamp,
        address initiatedBy
    );
    event MaxTokenIdsLengthUpdated(
        uint oldLength,
        uint newLength,
        uint256 timestamp,
        address initiatedBy
    );
    event SeasonStartTimestampUpdated(
        uint oldTimestamp,
        uint newTimestamp,
        uint256 timestamp,
        address initiatedBy
    );
    event SeasonEndTimestampUpdated(
        uint oldTimestamp,
        uint newTimestamp,
        uint256 timestamp,
        address initiatedBy
    );
    event GracePeriodTimestampUpdated(
        uint oldTimestamp,
        uint newTimestamp,
        uint256 timestamp,
        address initiatedBy
    );
    event CollectionUnplugableStatusUpdated(
        address indexed collectionAddress,
        bool status,
        uint256 timestamp,
        address initiatedBy
    );
    event NexusGemCollectionUpdated(
        address indexed oldCollection,
        address indexed newCollection,
        uint256 timestamp,
        address initiatedBy
    );
    event RgCollectionUpdated(
        address indexed oldCollection,
        address indexed newCollection,
        uint256 timestamp,
        address initiatedBy
    );
    event ImmortalCollectionUpdated(
        address indexed oldCollection,
        address indexed newCollection,
        uint256 timestamp,
        address initiatedBy
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner,
        uint256 timestamp,
        address initiatedBy
    );
    event PluggedTimeExtended(
        address indexed user,
        address indexed collection,
        uint256[] tokenIds,
        uint256 newPluggedUntil,
        uint256 timestamp
    );
    event ExtendedPluggingTimestampUpdated(
        uint oldTimestamp,
        uint newTimestamp,
        uint256 timestamp,
        address initiatedBy
    );

    event ExtendableBeforeTimestampUpdated(
        uint oldTimestamp,
        uint newTimestamp,
        uint256 timestamp,
        address initiatedBy
    );

    event ExtendedAllNFTs(
        address indexed user,
        uint256 timestamp
    );

    struct PlugDetails {
        address owner;
        uint256 tokenId;
        uint256 pluggedAt;
        uint256 pluggedUntil;
    }

    struct ScoutNodeDetails {
        address owner;
        string id;
        uint claimedAt;
    }

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    IERC721Upgradeable public _nexusGem;
    IERC721Upgradeable public _rgBytes;
    IERC721Upgradeable public _immortals;
    uint public _seasonStartTimestamp;
    uint public _seasonEndTimestamp;
    uint public _gracePeriodTimestamp;
    uint public _maxTokenIdsLength;
    address public _treasury;

    mapping(address => mapping(uint256 => PlugDetails)) public _plugDetails;
    mapping(address => mapping(address => EnumerableSetUpgradeable.UintSet)) _pluggedTokenIds;

    mapping(address => mapping(uint256 => ScoutNodeDetails))
        public _scoutNodeDetails;
    mapping(address => mapping(address => EnumerableSetUpgradeable.UintSet)) _claimedScoutNodes;

    mapping(address => mapping(uint => bool)) public _isTokenEverPlugged;
    mapping(address => bool) public _isUnplugable;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint public _extendedPluggingTimestamp;
    uint public _extendableBeforeTimestamp;

    mapping (address => bool) public _hasExtendedAll;

    // V2 States
    bytes32 public constant PLUG_DETAILS_REMOVAL_ROLE = keccak256("PLUG_DETAILS_REMOVAL_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address nexusGem,
        address rgBytes,
        address immortals,
        address admin,
        address treasury
    ) public initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _isValidAddress(nexusGem);
        _isValidAddress(rgBytes);
        _isValidAddress(immortals);
        _isValidAddress(treasury);

        _nexusGem = IERC721Upgradeable(nexusGem);
        _rgBytes = IERC721Upgradeable(rgBytes);
        _immortals = IERC721Upgradeable(immortals);

        _maxTokenIdsLength = 75;
        _treasury = treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    function plug(
        address collectionAddress,
        uint256[] calldata tokenIds
    ) external nonReentrant whenNotPaused {
        _isValidColllectionAddress(collectionAddress);
        _isValidTokenIdsArray(tokenIds);
        IERC721Upgradeable nftContract = IERC721Upgradeable(collectionAddress);

        uint256 currentTimestamp = block.timestamp;

        uint256 pluggedAt = currentTimestamp <= _gracePeriodTimestamp
            ? _seasonStartTimestamp
            : currentTimestamp;

        require(
            currentTimestamp >= _seasonStartTimestamp &&
                currentTimestamp <= _seasonEndTimestamp,
            "Plugging: Season has not started yet or has ended"
        );

        uint256 arrayLength = tokenIds.length;

        for (uint i; i < arrayLength; i++) {
            require(
                nftContract.ownerOf(tokenIds[i]) == msg.sender,
                "Plugging: You don't own all token"
            );

            // if (
            // !_isTokenEverPlugged[collectionAddress][tokenIds[i]] &&
            // collectionAddress != address(_immortals)
            // ) {
            // _isTokenEverPlugged[collectionAddress][tokenIds[i]] = true;

            // string memory collectionName = _getCollectionName(
            // collectionAddress
            // );
            // string memory scoutNodeId = _concatenateString(
            // collectionName,
            // Strings.toString(tokenIds[i])
            // );

            // _scoutNodeDetails[collectionAddress][
            // tokenIds[i]
            // ] = ScoutNodeDetails(msg.sender, scoutNodeId, pluggedAt);
            // _claimedScoutNodes[collectionAddress][msg.sender].add(
            // tokenIds[i]
            // );
            // }

            _plugDetails[collectionAddress][tokenIds[i]] = PlugDetails(
                msg.sender,
                tokenIds[i],
                pluggedAt,
                _seasonEndTimestamp
            );
            _pluggedTokenIds[collectionAddress][msg.sender].add(tokenIds[i]);
            nftContract.transferFrom(msg.sender, _treasury, tokenIds[i]);
        }
        emit Plugged(
            msg.sender,
            collectionAddress,
            tokenIds,
            pluggedAt,
            _seasonEndTimestamp
        );
    }

    function unplug(
        address collectionAddress,
        uint256[] calldata tokenIds
    ) external nonReentrant whenNotPaused {
        _isValidColllectionAddress(collectionAddress);
        _isValidTokenIdsArray(tokenIds);
        _isCollectionUnplugable(collectionAddress);

        uint256 currentTimestamp = block.timestamp;
        uint256 arrayLength = tokenIds.length;
        
        if (_hasExtendedAll[msg.sender]) {
            require(
                currentTimestamp >= _extendedPluggingTimestamp,
                "Plugging: Can't unplug before the extended plugging time"
            );
        }

        for (uint i; i < arrayLength; i++) {
            require(
                _plugDetails[collectionAddress][tokenIds[i]].owner ==
                    msg.sender,
                "Plugging: You don't own all plug"
            );

            require(
                currentTimestamp >=
                    _plugDetails[collectionAddress][tokenIds[i]].pluggedUntil,
                "Plugging: Can't unplug before the pluggedUntil time"
            );

            delete _plugDetails[collectionAddress][tokenIds[i]];
            _pluggedTokenIds[collectionAddress][msg.sender].remove(tokenIds[i]);
            IERC721Upgradeable(collectionAddress).transferFrom(
                _treasury,
                msg.sender,
                tokenIds[i]
            );
        }

        emit Unplugged(
            msg.sender,
            collectionAddress,
            tokenIds,
            currentTimestamp
        );
    }

    function extendPluggedTime(
        address collectionAddress,
        uint256[] memory tokenIds
    ) external nonReentrant whenNotPaused {
        _isValidColllectionAddress(collectionAddress);
        _isValidTokenIdsArray(tokenIds);
        _hasNotExtendedAll(msg.sender);

        require(
            block.timestamp <=
                _extendableBeforeTimestamp,
            "Plugging: Can't extend after the allowed extended plugging time"
        );

        for (uint i; i < tokenIds.length; i++) {
            require(
                _plugDetails[collectionAddress][tokenIds[i]].owner ==
                    msg.sender,
                "Plugging: You don't own this plug"
            );


            _plugDetails[collectionAddress][tokenIds[i]]
                .pluggedUntil = _extendedPluggingTimestamp;
        }

        emit PluggedTimeExtended(
            msg.sender,
            collectionAddress,
            tokenIds,
            _extendedPluggingTimestamp,
            block.timestamp
        );
    }

    function extendAllPluggedNfts() external nonReentrant whenNotPaused {
        _isValidAddress(msg.sender);
        _hasNotExtendedAll(msg.sender);

        _hasExtendedAll[msg.sender] = true;
        emit ExtendedAllNFTs(msg.sender, block.timestamp);
    }

    function removePluggedDetails(address userAddress, address collectionAddress, uint256 tokenId) public onlyRole(PLUG_DETAILS_REMOVAL_ROLE) {
        delete _plugDetails[collectionAddress][tokenId];
        _pluggedTokenIds[collectionAddress][userAddress].remove(tokenId);
    }

    function updateTreasuryAddress(
        address treasury
    ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        _isValidAddress(treasury);
        address oldTreasury = _treasury;
        _treasury = treasury;
        emit TreasuryAddressUpdated(
            oldTreasury,
            treasury,
            block.timestamp,
            msg.sender
        );
    }

    function updateMaxTokenIdsLength(
        uint length
    ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(length > 0, "Plugging: Invalid array length");
        uint oldLength = _maxTokenIdsLength;
        _maxTokenIdsLength = length;
        emit MaxTokenIdsLengthUpdated(
            oldLength,
            length,
            block.timestamp,
            msg.sender
        );
    }

    function updateSeasonStartTimestamp(
        uint timestamp
    ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(timestamp > 0, "Plugging: Invalid timestamp");
        uint oldTimestamp = _seasonStartTimestamp;
        _seasonStartTimestamp = timestamp;
        emit SeasonStartTimestampUpdated(
            oldTimestamp,
            timestamp,
            block.timestamp,
            msg.sender
        );
    }

    function updateSeasonEndTimestamp(
        uint timestamp
    ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(timestamp > _gracePeriodTimestamp, "Plugging: Timestamp should be greater than the grace period timestamp");
        uint oldTimestamp = _seasonEndTimestamp;
        _seasonEndTimestamp = timestamp;
        emit SeasonEndTimestampUpdated(
            oldTimestamp,
            timestamp,
            block.timestamp,
            msg.sender
        );
    }

    function updateGracePeriodTimestamp(
        uint timestamp
    ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(timestamp > _seasonStartTimestamp, "Plugging: Timestamp should be greater than the season start timestamp");
        uint oldTimestamp = _gracePeriodTimestamp;
        _gracePeriodTimestamp = timestamp;
        emit GracePeriodTimestampUpdated(
            oldTimestamp,
            timestamp,
            block.timestamp,
            msg.sender
        );
    }

    function updateExtendedPluggingTimestamp(
        uint timestamp
    ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(timestamp > _seasonEndTimestamp, "Plugging: Timestamp should be greater than the season end timestamp");
        uint oldTimestamp = _extendedPluggingTimestamp;
        _extendedPluggingTimestamp = timestamp;
        emit ExtendedPluggingTimestampUpdated(
            oldTimestamp,
            timestamp,
            block.timestamp,
            msg.sender
        );
    }

    function updateExtendableBeforeTimestamp(
        uint timestamp
    ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(timestamp < _extendedPluggingTimestamp, "Plugging: Timestamp should be less than the extended plugging timestamp");
        uint oldTimestamp = _extendableBeforeTimestamp;
        _extendableBeforeTimestamp = timestamp;
        emit ExtendableBeforeTimestampUpdated(
            oldTimestamp,
            timestamp,
            block.timestamp,
            msg.sender
        );
    }

    function updateCollectionUnplugableStatus(
        address[] calldata collectionAddresses,
        bool[] calldata statuses
    ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(
            collectionAddresses.length == statuses.length,
            "Plugging: Array length miss-match"
        );

        for (uint i; i < collectionAddresses.length; i++) {
            _isValidColllectionAddress(collectionAddresses[i]);
            _isUnplugable[collectionAddresses[i]] = statuses[i];
            emit CollectionUnplugableStatusUpdated(
                collectionAddresses[i],
                statuses[i],
                block.timestamp,
                msg.sender
            );
        }
    }

    function updateNexusGemCollection(
        address collectionAddress
    ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        _isValidContractAddress(collectionAddress);
        address oldCollection = address(_nexusGem);
        _nexusGem = IERC721Upgradeable(collectionAddress);
        emit NexusGemCollectionUpdated(
            oldCollection,
            collectionAddress,
            block.timestamp,
            msg.sender
        );
    }

    function updateRgCollection(
        address collectionAddress
    ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        _isValidContractAddress(collectionAddress);
        address oldCollection = address(_rgBytes);
        _rgBytes = IERC721Upgradeable(collectionAddress);
        emit RgCollectionUpdated(
            oldCollection,
            collectionAddress,
            block.timestamp,
            msg.sender
        );
    }

    function updateImmortalCollection(
        address collectionAddress
    ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        _isValidContractAddress(collectionAddress);
        address oldCollection = address(_immortals);
        _immortals = IERC721Upgradeable(collectionAddress);
        emit ImmortalCollectionUpdated(
            oldCollection,
            collectionAddress,
            block.timestamp,
            msg.sender
        );
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function transferContractOwnership(
        address newOwner
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _isValidAddress(newOwner);

        address oldOwner = msg.sender;

        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _revokeRole(PAUSER_ROLE, msg.sender);
        _revokeRole(UPGRADER_ROLE, msg.sender);

        _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        _grantRole(PAUSER_ROLE, newOwner);
        _grantRole(UPGRADER_ROLE, newOwner);

        emit OwnershipTransferred(
            oldOwner,
            newOwner,
            block.timestamp,
            msg.sender
        );
    }

    function getUserPluggedTokenIds(
        address collectionAddress,
        address userAddress
    ) public view returns (uint[] memory) {
        return _pluggedTokenIds[collectionAddress][userAddress].values();
    }

    function getUserScoutNodeIds(
        address collectionAddress,
        address userAddress
    ) public view returns (uint[] memory) {
        return _claimedScoutNodes[collectionAddress][userAddress].values();
    }

    function getUserPluggedNFTs(
        address collectionAddress,
        address userAddress
    ) public view returns (PlugDetails[] memory) {
        uint256[] memory pluggedTokenIds = _pluggedTokenIds[collectionAddress][
            userAddress
        ].values();
        PlugDetails[] memory pluggedDetails = new PlugDetails[](
            pluggedTokenIds.length
        );
        for (uint256 i = 0; i < pluggedTokenIds.length; i++) {
            pluggedDetails[i] = _plugDetails[collectionAddress][
                pluggedTokenIds[i]
            ];
        }
        return pluggedDetails;
    }

    function getUserScoutNodesPerCollection(
        address collectionAddress,
        address userAddress
    ) public view returns (ScoutNodeDetails[] memory) {
        uint256[] memory scoutNodesIds = _claimedScoutNodes[collectionAddress][
            userAddress
        ].values();
        ScoutNodeDetails[] memory scoutNodes = new ScoutNodeDetails[](
            scoutNodesIds.length
        );
        for (uint256 i = 0; i < scoutNodesIds.length; i++) {
            scoutNodes[i] = _scoutNodeDetails[collectionAddress][
                scoutNodesIds[i]
            ];
        }
        return scoutNodes;
    }

    function getUserPluggedNFTs(
        address userAddress
    )
        public
        view
        returns (
            PlugDetails[] memory,
            PlugDetails[] memory,
            PlugDetails[] memory
        )
    {
        uint256[] memory gemPluggedTokenIds = _pluggedTokenIds[
            address(_nexusGem)
        ][userAddress].values();
        uint256[] memory rgPluggedTokenIds = _pluggedTokenIds[
            address(_rgBytes)
        ][userAddress].values();
        uint256[] memory immortalPluggedTokenIds = _pluggedTokenIds[
            address(_immortals)
        ][userAddress].values();

        PlugDetails[] memory pluggedGemDetails = new PlugDetails[](
            gemPluggedTokenIds.length
        );
        PlugDetails[] memory pluggedRgDetails = new PlugDetails[](
            rgPluggedTokenIds.length
        );
        PlugDetails[] memory pluggedImmortalDetails = new PlugDetails[](
            immortalPluggedTokenIds.length
        );
        for (uint256 i = 0; i < gemPluggedTokenIds.length; i++) {
            pluggedGemDetails[i] = _plugDetails[address(_nexusGem)][
                gemPluggedTokenIds[i]
            ];
        }
        for (uint256 i = 0; i < rgPluggedTokenIds.length; i++) {
            pluggedRgDetails[i] = _plugDetails[address(_rgBytes)][
                rgPluggedTokenIds[i]
            ];
        }
        for (uint256 i = 0; i < immortalPluggedTokenIds.length; i++) {
            pluggedImmortalDetails[i] = _plugDetails[address(_immortals)][
                immortalPluggedTokenIds[i]
            ];
        }
        return (pluggedGemDetails, pluggedRgDetails, pluggedImmortalDetails);
    }

    function getUserScoutNodes(
        address userAddress
    )
        public
        view
        returns (ScoutNodeDetails[] memory, ScoutNodeDetails[] memory)
    {
        uint256[] memory gemScoutNodeIds = _claimedScoutNodes[
            address(_nexusGem)
        ][userAddress].values();
        uint256[] memory rgScoutNodeIds = _claimedScoutNodes[address(_rgBytes)][
            userAddress
        ].values();
        ScoutNodeDetails[] memory gemScoutNodeDetails = new ScoutNodeDetails[](
            gemScoutNodeIds.length
        );
        ScoutNodeDetails[] memory rgScoutNodeDetails = new ScoutNodeDetails[](
            rgScoutNodeIds.length
        );
        for (uint256 i = 0; i < gemScoutNodeIds.length; i++) {
            gemScoutNodeDetails[i] = _scoutNodeDetails[address(_nexusGem)][
                gemScoutNodeIds[i]
            ];
        }
        for (uint256 i = 0; i < rgScoutNodeIds.length; i++) {
            rgScoutNodeDetails[i] = _scoutNodeDetails[address(_rgBytes)][
                rgScoutNodeIds[i]
            ];
        }
        return (gemScoutNodeDetails, rgScoutNodeDetails);
    }

    function _getCollectionName(
        address collection
    ) private view returns (string memory) {
        if (collection == address(_nexusGem)) {
            return "gem_";
        } else if (collection == address(_rgBytes)) {
            return "rg_";
        }
        return "";
    }

    function _concatenateString(
        string memory str1,
        string memory str2
    ) private pure returns (string memory) {
        return string(abi.encodePacked(str1, str2));
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}

    function _isValidColllectionAddress(address addr) private view {
        require(
            addr == address(_immortals) ||
                addr == address(_rgBytes) ||
                addr == address(_nexusGem),
            "Plugging: Invalid collection address"
        );
    }

    function _isValidContractAddress(address addr) private view {
        require(addr.code.length > 0, "Plugging: Invalid contract address");
    }

    function _isValidAddress(address addr) private pure {
        require(addr != address(0), "Plugging: Invalid address");
    }

    function _isValidTokenIdsArray(uint[] memory tokenIds) private view {
        require(
            tokenIds.length <= _maxTokenIdsLength,
            "Plugging: TokenIds array <= max allowed length"
        );
    }

    function _isCollectionUnplugable(address collectionAddress) private view {
        require(
            _isUnplugable[collectionAddress],
            "Plugging: Cannot unplug NFTs from this collection"
        );
    }

    function _hasNotExtendedAll(address userAddress) private view {
        require(
            !_hasExtendedAll[userAddress],
            "Plugging: Already extended all NFTs"
        );
    }
}
