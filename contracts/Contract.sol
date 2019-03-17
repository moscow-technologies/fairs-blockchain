pragma solidity ^0.5.2;

contract Owned {
    address public owner;

    constructor() public {
        owner = tx.origin;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    modifier onlyOrigin {
        require(tx.origin == owner);
        _;
    }

    function isDeployed() public pure returns (bool) {
        return true;
    }
}

contract ISeason is Owned {
    function begin() public view returns (uint64);
    function end() public view returns (uint64);
    function getHistoricalIndices() public view returns (uint64[] memory);
    function getRequestByIndex(uint64) public view returns (bytes30, uint64, Types.DeclarantType, string memory, uint64, Types.Speciality, uint64, uint64, string memory, uint64[] memory, bytes16);
    function getStatusUpdates(bytes30) public view returns (uint64[] memory, uint64[] memory, string memory);
    function getLatestStatus(uint64 index) public view returns (uint64);
}

contract IDistributor is Owned {
    function isLoaded() public view returns (bool);
    function isDistributed() public view returns (bool);
    function loadRequests() public;
    function distribute() public;
    function getPeriodsCount() public view returns(uint64);
    function getPeriod(uint64 index) public view returns(uint64, uint64, bytes30[] memory, bytes30[] memory, bytes30[] memory, Types.Speciality);
    function init(uint64[] memory fairsIds, uint64[] memory periods, Types.Speciality[] memory specialities, uint64[] memory placesCount) public;
    function getUnoccupiedPlaces() public view returns(uint64[] memory, bool[] memory);
    function getRequestedPlaces() public view returns(uint64[] memory);
    function updatePlaces(uint64[] memory placesCounts) public;
    function finalizeWaitingLists() public;
}

contract SeasonFactory is Owned {
    address[] public seasons;
    address[] public distributions;
    address public newVersionAddress;

    event SeasonCreated(uint64 indexed begin, uint64 indexed end, address season);

    function migrateToNewVersion(address newVersionAddress_) public onlyOwner {
        require(newVersionAddress == address(0));
        require(newVersionAddress_ != address(this));

        SeasonFactory newVersion = SeasonFactory(newVersionAddress_);
        require(newVersion.owner() == owner);
        require(newVersion.isDeployed());

        newVersionAddress = newVersionAddress_;
    }

    function addSeason(address seasonAddress) public onlyOwner {
        if (newVersionAddress != address(0)) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            newVersion.addSeason(seasonAddress);
            return;
        }

        ISeason season = ISeason(seasonAddress);
        require(season.owner() == owner);
        require(seasons.length == 0 || ISeason(seasons[seasons.length - 1]).end() < season.begin());

        seasons.push(seasonAddress);
        emit SeasonCreated(season.begin(), season.end(), seasonAddress);
    }

    function addDistribution(address distributionManagerAddress) public onlyOwner {
        if (newVersionAddress != address(0)) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            newVersion.addDistribution(distributionManagerAddress);
            return;
        }

        Owned distributionManager = Owned(distributionManagerAddress);
        require(distributionManager.owner() == owner);

        distributions.push(distributionManagerAddress);
    }

    function getDistributionsCount() public view returns (uint64) {
        if (newVersionAddress != address(0)) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            return newVersion.getDistributionsCount();
        }

        return uint64(distributions.length);
    }

    function getSeasonsCount() public view returns (uint64) {
        if (newVersionAddress != address(0)) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            return newVersion.getSeasonsCount();
        }

        return uint64(seasons.length);
    }

    function getLastSeason() public view returns (address) {
        if (newVersionAddress != address(0)) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            return newVersion.getLastSeason();
        }

        if (seasons.length == 0) {
            return address(0);
        }

        return seasons[seasons.length - 1];
    }
}

contract Season is Owned {
    uint64 public begin;
    uint64 public end;
    string name;

    uint64 requestCount;
    Node[] nodes;
    uint64 headIndex;
    uint64 tailIndex;
    mapping(bytes30 => uint64) requestServiceNumberToIndex;

    event RequestCreated(bytes30 indexed serviceNumber, uint64 index);

    constructor(uint64 begin_, uint64 end_, string memory name_) public {
        begin = begin_;
        end = end_;
        name = name_;
    }

    function createRequest(bytes30 serviceNumber, uint64 date, uint64 regNum, Types.DeclarantType declarantType, string memory declarantName, uint64 fairId, Types.Speciality speciality, uint64 district, uint64 region, string memory details, uint64[] memory periods, bytes16 userId) public onlyOwner {
        validateServiceNumber(serviceNumber);

        nodes.length++;
        uint64 newlyInsertedIndex = getRequestsCount() - 1;
        uint128 dateRegNumPair = (uint128(date) << 64) | uint128(regNum);

        Request storage request = nodes[newlyInsertedIndex].request;
        request.serviceNumber = serviceNumber;
        request.date = date;
        request.regNum = regNum;
        request.dateRegNumPair = dateRegNumPair;
        request.declarantType = declarantType;
        request.declarantName = declarantName;
        request.fairId = fairId;
        request.district = district;
        request.region = region;
        request.speciality = speciality;
        request.details = details;
        request.periods = periods;
        request.userId = userId;
        requestServiceNumberToIndex[request.serviceNumber] = newlyInsertedIndex;
        pushCreatedStatusUpdate(request, date);

        fixPlacementInHistory(newlyInsertedIndex, dateRegNumPair);

        emit RequestCreated(serviceNumber, newlyInsertedIndex);
    }

    function setRequestDeclarantTypeToFarmer(bytes30 serviceNumber) public onlyOwner {
        require(!isNewRequest(serviceNumber), "Request with provided service number was not found");
        
        int index = getRequestIndex(serviceNumber);
        Request storage request = nodes[uint64(index)].request;
        request.declarantType = Types.DeclarantType.Farmer;
    }

    function setRequestPeriods(bytes30 serviceNumber, uint64 statusCode, uint64 responseDate, uint64 fairId, uint64[] memory periods,  uint64[] memory periodStatusCodes, string memory details) public onlyOwner {
        require(!isNewRequest(serviceNumber), "Request with provided service number was not found");

        int index = getRequestIndex(serviceNumber);
        Request storage request = nodes[uint64(index)].request;

        request.periods.length = 0;

        for (uint i = 0; i < periods.length; i++) {
            // Periods with status codes "Rejected" and "Cancelled by user" don't get into distribution
            if (periodStatusCodes[i] != 1080 && periodStatusCodes[i] != 1190) {
                request.periods.push(periods[i]);
            }
        }

        updateStatusInternal(request, responseDate, statusCode, "");

        request.fairId = fairId;
        request.details = details;
     }

    function fixPlacementInHistory(uint64 newlyInsertedIndex, uint128 dateRegNumPair) private onlyOwner {
        if (newlyInsertedIndex == 0) {
            nodes[0].prev = -1;
            nodes[0].next = -1;
            return;
        }

        int index = tailIndex;
        while (index >= 0) {
            Node storage n = nodes[uint64(index)];
            if (n.request.dateRegNumPair <= dateRegNumPair) {
                break;
            }
            index = n.prev;
        }

        if (index < 0) {
            nodes[headIndex].prev = newlyInsertedIndex;
            nodes[newlyInsertedIndex].next = headIndex;
            nodes[newlyInsertedIndex].prev = -1;
            headIndex = newlyInsertedIndex;
        }
        else {
            Node storage node = nodes[uint64(index)];
            Node storage newNode = nodes[newlyInsertedIndex];
            newNode.prev = index;
            newNode.next = node.next;
            if (node.next > 0) {
                nodes[uint64(node.next)].prev = newlyInsertedIndex;
            } else {
                tailIndex = newlyInsertedIndex;
            }
            node.next = newlyInsertedIndex;
        }
    }

    function updateStatus(bytes30 serviceNumber, uint64 responseDate, uint64 statusCode, string memory note) public onlyOwner {
        require(!isNewRequest(serviceNumber), "Request with provided service number was not found");
        require(isNewStatus(serviceNumber, responseDate, statusCode, note), "Duplicate statuses are not allowed");
        int index = getRequestIndex(serviceNumber);
        Request storage request = nodes[uint64(index)].request;
        updateStatusInternal(request, responseDate, statusCode, note);
    }

    function isNewStatus(bytes30 serviceNumber, uint64 responseDate, uint64 statusCode, string memory note) public view returns(bool) {
        int index = getRequestIndex(serviceNumber);

        Request storage request = nodes[uint64(index)].request;
        for (uint64 i = 0; i < request.statusUpdates.length; i++) {
            Types.StatusUpdate storage update = request.statusUpdates[i];
            if (
                update.responseDate == responseDate
                && update.statusCode == statusCode
                && bytes(update.note).length == bytes(note).length && containsString(update.note, note)
            ) {
                return false;
            }
        }
        return true;
    }

    function updateStatusInternal(Request storage request, uint64 responseDate, uint64 statusCode, string memory note) private {
        request.statusUpdates.push(Types.StatusUpdate(responseDate, statusCode, note));
        request.statusUpdatesNotes = strConcat(request.statusUpdatesNotes, "\x1f", note);
    }

    function getSeasonDetails() public view returns (uint64, uint64, string memory) {
        return (begin, end, name);
    }

    function getAllServiceNumbers() public view returns (bytes30[] memory) {
        bytes30[] memory result = new bytes30[](getRequestsCount());
        for (uint64 i = 0; i < result.length; i++) {
            result[i] = nodes[i].request.serviceNumber;
        }
        return result;
    }

    function getHistoricalIndices() public view returns (uint64[] memory){
        uint64[] memory result = new uint64[](getRequestsCount());
        int currentIndex = headIndex;
        for (uint64 i = 0; i < nodes.length; i++) {
            Node storage node = nodes[uint64(currentIndex)];
            result[i] = uint64(currentIndex);
            currentIndex = node.next;
        }
        return result;
    }

    function getLatestStatus(uint64 index) public view returns (uint64) {
        Node storage node = nodes[uint64(index)];
        Types.StatusUpdate[] storage statusUpdates = node.request.statusUpdates;
        uint latestStatusIndex = statusUpdates.length - 1;
        for (uint i = latestStatusIndex; ; i--) {
            if (statusUpdates[latestStatusIndex].responseDate < statusUpdates[i].responseDate) {
                latestStatusIndex = i;
            }
            if (i == 0) {
                break;
            }
        }
        uint64 latestStatus = statusUpdates[latestStatusIndex].statusCode;
        return latestStatus;
    }

    function getRequestIndex(bytes30 serviceNumber) public view returns (int) {
        uint64 index = requestServiceNumberToIndex[serviceNumber];

        if (index == 0 && (nodes.length == 0 || nodes[0].request.serviceNumber != serviceNumber)) {
            return - 1;
        }

        return int(index);
    }

    function getRequestByServiceNumber(bytes30 serviceNumber) public view returns (bytes30, uint64, Types.DeclarantType, string memory, uint64, Types.Speciality, uint64, uint64, string memory, uint64[] memory, bytes16, uint64) {
        int index = getRequestIndex(serviceNumber);

        if (index < 0) {
            return (0, 0, Types.DeclarantType.Individual, "", 0, Types.Speciality.UNUSED, 0, 0, "", new uint64[](0), 0, 0);
        }

        return getRequestByIndex(uint64(index));
    }

    function getRequestByIndex(uint64 index) public view returns (bytes30, uint64, Types.DeclarantType, string memory, uint64, Types.Speciality, uint64, uint64, string memory, uint64[] memory, bytes16, uint64) {
        Request storage request = nodes[index].request;
        return (request.serviceNumber, request.date, request.declarantType, request.declarantName, request.fairId, request.speciality, request.district, request.region, request.details, request.periods, request.userId, request.regNum);
    }

    function getRequestsCount() public view returns (uint64) {
        return uint64(nodes.length);
    }

    function getStatusUpdates(bytes30 serviceNumber) public view returns (uint64[] memory, uint64[] memory, string memory) {
        int index = getRequestIndex(serviceNumber);

        if (index < 0) {
            return (new uint64[](0), new uint64[](0), "");
        }

        Request storage request = nodes[uint64(index)].request;
        uint64[] memory dates = new uint64[](request.statusUpdates.length);
        uint64[] memory statusCodes = new uint64[](request.statusUpdates.length);
        for (uint64 i = 0; i < request.statusUpdates.length; i++) {
            dates[i] = request.statusUpdates[i].responseDate;
            statusCodes[i] = request.statusUpdates[i].statusCode;
        }

        return (dates, statusCodes, request.statusUpdatesNotes);
    }

    function getMatchingRequests(uint64 skipCount, uint64 takeCount, Types.DeclarantType[] memory declarantTypes, string memory declarantName, uint64 fairId, Types.Speciality speciality, uint64 district) public view returns (uint64[] memory, uint64) {
        uint64[] memory result = new uint64[](takeCount);
        uint64 skippedCount = 0;
        uint64 tookCount = 0;
        int currentIndex = headIndex;
        for (uint64 i = 0; i < nodes.length && tookCount < result.length; i++) {
            Node storage node = nodes[uint64(currentIndex)];
            if (isMatch(node.request, declarantTypes, declarantName, fairId, speciality, district)) {
                if (skippedCount < skipCount) {
                    skippedCount++;
                }
                else {
                    result[tookCount++] = uint64(currentIndex);
                }
            }
            currentIndex = node.next;
        }

        return (result, tookCount);
    }

    function isMatch(Request memory request, Types.DeclarantType[] memory declarantTypes, string memory declarantName_, uint64 fairId_, Types.Speciality speciality_, uint64 district_) private pure returns (bool) {
        if (declarantTypes.length != 0 && !containsDeclarant(declarantTypes, request.declarantType)) {
            return false;
        }
        if (!isEmpty(declarantName_) && !containsString(request.declarantName, declarantName_)) {
            return false;
        }
        if (fairId_ != 0 && fairId_ != request.fairId) {
            return false;
        }
        if (district_ != 0 && district_ != request.district) {
            return false;
        }
        if (speciality_ != Types.Speciality.UNUSED && speciality_ != request.speciality) {
            return false;
        }
        return true;
    }

    function containsDeclarant(Types.DeclarantType[] memory array, Types.DeclarantType value) private pure returns (bool) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == value)
                return true;
        }
        return false;
    }

    function validateServiceNumber(bytes30 serviceNumber) private view {
	    require(isNewRequest(serviceNumber), "Request with provided service number already exists");
    }

    function isNewRequest(bytes30 serviceNumber) public view returns(bool) {
	    return getRequestIndex(serviceNumber) < 0;
    }

    function pushCreatedStatusUpdate(Request storage request, uint64 date) private {
        request.statusUpdates.push(Types.StatusUpdate(date, 1010, ""));
    }

    function isEmpty(string memory value) private pure returns (bool) {
        return bytes(value).length == 0;
    }

    function containsString(string memory _base, string memory _value) internal pure returns (bool) {
        bytes memory _baseBytes = bytes(_base);
        bytes memory _valueBytes = bytes(_value);

        if (_baseBytes.length < _valueBytes.length) {
            return false;
        }

        for (uint j = 0; j <= _baseBytes.length - _valueBytes.length; j++) {
            uint i = 0;
            for (; i < _valueBytes.length; i++) {
                if (_baseBytes[i + j] != _valueBytes[i]) {
                    break;
                }
            }

            if (i == _valueBytes.length)
                return true;
        }

        return false;
    }

    function strConcat(string memory a, string memory b, string memory c) private pure returns (string memory) {
        return string(abi.encodePacked(a,b,c));
    }

    struct Node {
        Request request;
        int prev;
        int next;
    }

    struct Request {
        bytes30 serviceNumber;
        uint64 date;
        uint64 regNum;
        uint128 dateRegNumPair;
        Types.DeclarantType declarantType;
        string declarantName;
        uint64 fairId;
        Types.Speciality speciality;
        uint64[] periods;
        uint64 district; // округ
        uint64 region; // район
        Types.StatusUpdate[] statusUpdates;
        string statusUpdatesNotes;
        string details;
        bytes16 userId;
    }
}

library Types {
    struct StatusUpdate {
        uint64 responseDate;
        uint64 statusCode;
        string note;
    }

    enum DeclarantType {
        Individual, // ФЛ
        IndividualEntrepreneur, // ИП
        LegalEntity, // ЮЛ
        IndividualAsIndividualEntrepreneur, // ФЛ как ЮЛ
        Farmer // ИП КФХ
    }

    struct DistributorRequest {
        bytes30 serviceNumber;
        bytes16 userId;
        Types.DeclarantType declarantType;
        uint64 fairId;
        uint64[] periods;
        Types.Speciality speciality;
    }

    enum RedistributionResult {
        AllPeriodsAreSet,
        NeedDistributionRerun
    }

    struct RedistributionInfo {
        bool wasRedistributedToIndividuals;
        bool wasRedistributedToindividuals;
        bool wasRedistributedToIELEs;
    }

    struct FairPeriod {
        uint64 fairId;
        uint64 date;
        uint64 placesCount;
        Types.Speciality speciality;
        bytes30[] serviceNumbers;
        bytes30[] waitingList;
        bytes30[] rejectedServiceNumbers;
        bytes30[] allRequests;

        mapping(bytes30 => bool) isRequestFullyProcessed;
    }

    struct MaybeUninit {
        bool isInited;
        uint value;
    }

    enum Speciality
    {
        UNUSED,
        Vegetables,
        Meat,
        Fish,
        FoodStuffs
    }
}
