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
    function getHistoricalIndices() public view returns (uint64[] memory);
    function getRequestByIndex(uint64) public view returns (bytes30, uint64, Types.DeclarantType, string memory, uint64, Types.Speciality, uint64, uint64, string memory, uint64[] memory, bytes16);
    function getStatusUpdates(bytes30) public view returns (uint64[] memory, uint64[] memory, string memory);
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
    uint64[] seasonPeriodsBegins;
    uint64[] seasonBegins;
    uint64[] seasonEnds;

    event SeasonCreated(uint64 indexed begin, uint64 indexed end, address season);

    function migrateToNewVersion(address newVersionAddress_) public onlyOwner {
        require(newVersionAddress == address(0));
        require(newVersionAddress_ != address(this));

        SeasonFactory newVersion = SeasonFactory(newVersionAddress_);
        require(newVersion.owner() == owner);
        require(newVersion.isDeployed());

        newVersionAddress = newVersionAddress_;
    }

    function getSeasons() public view returns (address[] memory seasonAddresses, uint64[] memory seasonBegins_, uint64[] memory seasonEnds_, uint64[] memory seasonPeriodBegins_) {
        if (newVersionAddress != address(0)) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            return newVersion.getSeasons();
        }
        return (seasons, seasonBegins, seasonEnds, seasonPeriodsBegins);
    }

    function addSeason(address seasonAddress, uint64 seasonBegin, uint64 seasonEnd, uint64 seasonPeriodsBegin) public onlyOwner {
        if (newVersionAddress != address(0)) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            newVersion.addSeason(seasonAddress, seasonBegin, seasonEnd, seasonPeriodsBegin);
            return;
        }

        ISeason season = ISeason(seasonAddress);
        require(season.owner() == owner);

        seasons.push(seasonAddress);
        seasonBegins.push(seasonBegin);
        seasonEnds.push(seasonEnd);
        seasonPeriodsBegins.push(seasonPeriodsBegin);
        emit SeasonCreated(seasonBegin, seasonEnd, seasonAddress);
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

    function getSeasonForPeriod(uint64 period) public view returns (address) {
        if (newVersionAddress != address(0)) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            return newVersion.getSeasonForPeriod(period);
        }

        if (seasons.length == 0) {
            return address(0);
        }

        for (uint i = seasons.length - 1; ; i--) {
            if (seasonPeriodsBegins[i] <= period) {
                return seasons[i];
            }
            if (i == 0) {
                return address(0);
            }
        }
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
    string public name;

    uint64 requestCount;
    Node[] nodes;
    uint64 headIndex;
    uint64 tailIndex;
    mapping(bytes30 => uint64) requestServiceNumberToIndex;

    event RequestCreated(bytes30 indexed serviceNumber, uint64 index);

    constructor(string memory name_) public {
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
            return;
        }

        Types.OptionU64 memory currentIndex = Types.OptionU64(true, tailIndex);
        while (currentIndex.hasValue) {
            Node storage n = nodes[currentIndex.value];
            if (n.request.dateRegNumPair <= dateRegNumPair) {
                break;
            }
            currentIndex = n.prev;
        }

        if (!currentIndex.hasValue) {
            nodes[headIndex].prev = Types.OptionU64(true, newlyInsertedIndex);
            nodes[newlyInsertedIndex].next = Types.OptionU64(true, headIndex);
            headIndex = newlyInsertedIndex;
        }
        else {
            Node storage currentNode = nodes[currentIndex.value];
            Node storage newNode = nodes[newlyInsertedIndex];
            newNode.prev = currentIndex;
            newNode.next = currentNode.next;
            if (currentNode.next.hasValue) {
                nodes[currentNode.next.value].prev = Types.OptionU64(true, newlyInsertedIndex);
            } else if (currentIndex.value == tailIndex) {
                tailIndex = newlyInsertedIndex;
            }
            currentNode.next = Types.OptionU64(true, newlyInsertedIndex);
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

    function getSeasonDetails() public view returns (uint64, uint64, string memory name_) {	
        return (0, 0, name);	
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
        Types.OptionU64 memory currentIndex = Types.OptionU64(true, headIndex);
        for (uint64 i = 0; i < nodes.length; i++) {
            require(currentIndex.hasValue);
            Node storage node = nodes[currentIndex.value];
            result[i] = currentIndex.value;
            currentIndex = node.next;
        }
        return result;
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
        Types.OptionU64 memory currentIndex = Types.OptionU64(true, headIndex);
        for (uint64 i = 0; i < nodes.length && tookCount < result.length; i++) {
            require(currentIndex.hasValue);
            Node storage node = nodes[currentIndex.value];
            if (isMatch(node.request, declarantTypes, declarantName, fairId, speciality, district)) {
                if (skippedCount < skipCount) {
                    skippedCount++;
                }
                else {
                    result[tookCount++] = currentIndex.value;
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
        Types.OptionU64 prev;
        Types.OptionU64 next;
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

contract SeasonSnapshot is Owned {
    address public seasonAddress;
    uint64 public currentPosition;
    bool public isPositionSet;
    uint64[] historicalIndices;

    Types.DistributorRequest[] invididualsRequests;
    Types.DistributorRequest[] farmerRequests;
    Types.DistributorRequest[] ieLeRequests;

    constructor(address seasonAddress_) public {
        ISeason season = ISeason(seasonAddress_);
        require(season.owner() == owner);

        seasonAddress = seasonAddress_;
    }

    function loadHistoricalIndices() public onlyOwner {
        require(!isPositionSet, "Position is already set");

        ISeason season = ISeason(seasonAddress);
        uint64[] memory indices = season.getHistoricalIndices();
        for (uint i = 0; i < indices.length; i++) {
            uint64 index = indices[i];
            historicalIndices.push(index);
        }
        isPositionSet = true;
    }

    function isLoaded() public view returns (bool) {
        return isPositionSet && currentPosition >= historicalIndices.length;
    }

    function loadRequests() public onlyOwner {
        require(isPositionSet, "Position is not set");
        require(!isLoaded(), "Is already loaded");

        ISeason season = ISeason(seasonAddress);
        uint64 batchSize = 500;

        uint64 diff = uint64(historicalIndices.length) - currentPosition;
        uint64 iterCount = diff > batchSize ? batchSize : diff;

        for (uint i = 0; i < iterCount; i++) {
            uint64 historicalIndex = historicalIndices[currentPosition];
            currentPosition++;
            Types.DistributorRequest memory request = getRequest(season, historicalIndex);
            (uint64[] memory dates, uint64[] memory statusCodes, ) = season.getStatusUpdates(request.serviceNumber);
            Types.OptionU64 memory rejectionStatus = getRejectionStatus(dates, statusCodes);

            if (rejectionStatus.hasValue) {
                continue;
            }

            if (request.declarantType == Types.DeclarantType.Individual) {
                invididualsRequests.push(request);
            }
            else if (request.declarantType == Types.DeclarantType.Farmer && request.speciality == Types.Speciality.Vegetables) {
                // only requests with vegetables speciality gets promoted
                farmerRequests.push(request);
            }
            else if (request.declarantType == Types.DeclarantType.IndividualEntrepreneur
                     || request.declarantType == Types.DeclarantType.LegalEntity
                     || request.declarantType == Types.DeclarantType.Farmer
                     || request.declarantType == Types.DeclarantType.IndividualAsIndividualEntrepreneur) {
                ieLeRequests.push(request);
            } else {
                require (false, "Unexpected declarant type");
            }
        }
    }

    function getRequest(ISeason season, uint64 index) private view returns (Types.DistributorRequest memory) {
        (bytes30 serviceNumber, , Types.DeclarantType declarantType, , uint64 fairId, Types.Speciality speciality, , , , uint64[] memory periods, bytes16 userId) = season.getRequestByIndex(index);
        return Types.DistributorRequest(serviceNumber, userId, declarantType, fairId, getPeriodsWithRoundedDate(periods), speciality);
    }

    function getIndividualRequestsCount() public view returns (uint64) {
        return uint64(invididualsRequests.length);
    }

    function getIndividualRequest(uint index) public view returns (bytes30, bytes16, Types.DeclarantType, uint64, uint64[] memory, Types.Speciality speciality) {
        Types.DistributorRequest storage request = invididualsRequests[index];
        return (request.serviceNumber, request.userId, request.declarantType, request.fairId, request.periods, request.speciality);
    }

    function getFarmerRequestsCount() public view returns (uint64) {
        return uint64(farmerRequests.length);
    }

    function getFarmerRequest(uint index) public view returns (bytes30, bytes16, Types.DeclarantType, uint64, uint64[] memory, Types.Speciality speciality) {
        Types.DistributorRequest storage request = farmerRequests[index];
        return (request.serviceNumber, request.userId, request.declarantType, request.fairId, request.periods, request.speciality);
    }

    function getLeRequestsCount() public view returns (uint64) {
        return uint64(ieLeRequests.length);
    }

    function getLeRequest(uint index) public view returns (bytes30, bytes16, Types.DeclarantType, uint64, uint64[] memory, Types.Speciality speciality) {
        Types.DistributorRequest storage request = ieLeRequests[index];
        return (request.serviceNumber, request.userId, request.declarantType, request.fairId, request.periods, request.speciality);
    }

    function getHistoricalIndicesCount() public view returns (uint64) {
        return uint64(historicalIndices.length);
    }

    function getRejectionStatus(uint64[] memory dates, uint64[] memory statusCodes) private pure returns (Types.OptionU64 memory) {
        require (dates.length == statusCodes.length);
        require (dates.length > 0);
        Types.OptionU64 memory latestStatusIndex = Types.OptionU64(false, 0);
        for (uint64 i = uint64(dates.length - 1); ; i--) {
            if ((!latestStatusIndex.hasValue || dates[i] > dates[latestStatusIndex.value]) && isDistributionStatus(statusCodes[i])) {
                latestStatusIndex = Types.OptionU64(true, i);
            }
            if (i == 0) {
                break;
            }
        }

        if (!latestStatusIndex.hasValue) {
            return Types.OptionU64(true, 0); // has no distributable status
        }

        uint64 latestStatus = statusCodes[latestStatusIndex.value];
        if (isBadStatus(latestStatus)) {
            return Types.OptionU64(true, latestStatus);
        }

        return Types.OptionU64(false, 0);
    }

    function isDistributionStatus(uint64 statusCode) private pure returns (bool) {
        return statusCode == 1040
            || statusCode == 1050
            || statusCode == 77061
            || statusCode == 77062
            || statusCode == 1066
            || statusCode == 1086
            || isBadStatus(statusCode);
    }

    function isBadStatus(uint64 statusCode) private pure returns (bool) {
        return statusCode == 1080
            || statusCode == 1190
            || statusCode == 1086
            || statusCode == 103099;
    }

    function getPeriodsWithRoundedDate(uint64[] memory originalPeriods) private pure returns(uint64[] memory) {
        uint64[] memory result = new uint64[](originalPeriods.length);
        for (uint i = 0; i < result.length; i++) {
           result[i] = (((originalPeriods[i] / 36000000000)/24)*24)*36000000000;
        }
        return result;
    }
}

contract IndividualsDistributor is IDistributor {
    address public seasonSnapshotAddress;
    uint64 currentLoadPosition;
    uint64 currentDistributionPosition;
    bool isPositionSet;
    bool public isWaitingListFinalized;
    uint64 public requestsCount;
    Types.DistributorRequest[] requests;
    Types.FairPeriod[] allPeriods;
    mapping(uint256 => bytes30) registeredDeclarantRequests;
    mapping(uint256 => mapping(uint256 => Types.MaybeUninit)) fairsToPeriodsToSpecialitiesToPeriodIndex;

    constructor(address seasonSnapshotAddress_) public {
        SeasonSnapshot seasonSnapshot = SeasonSnapshot(seasonSnapshotAddress_);
        require(seasonSnapshot.owner() == owner);

        seasonSnapshotAddress = seasonSnapshotAddress_;
        requestsCount = seasonSnapshot.getIndividualRequestsCount();
    }

    function isLoaded() public view returns (bool) {
        return isPositionSet &&
            currentLoadPosition >= requestsCount;
    }

    function isDistributed() public view returns (bool) {
        return isLoaded() &&
            currentDistributionPosition >= requestsCount;
    }

    function init(uint64[] memory fairsIds, uint64[] memory periods, Types.Speciality[] memory specialities, uint64[] memory placesCount) public onlyOrigin {
        for (uint i = 0; i < fairsIds.length; i++) {
            Types.FairPeriod memory fairPeriod;
            fairPeriod.fairId = fairsIds[i];
            fairPeriod.date = periods[i];
            fairPeriod.placesCount = placesCount[i];
            fairPeriod.speciality = specialities[i];
            allPeriods.push(fairPeriod);
            if (specialities[i] == Types.Speciality.Vegetables) {
                 // only vegetables are allowed for individuals
                fairsToPeriodsToSpecialitiesToPeriodIndex[fairPeriod.fairId][fairPeriod.date] = Types.MaybeUninit(true, i);
            }
        }
        isPositionSet = true;
    }

    function loadRequests() public onlyOrigin {
        require(!isLoaded());

        SeasonSnapshot seasonSnapshot = SeasonSnapshot(seasonSnapshotAddress);
        uint64 batchSize = 500;

        uint64 diff = requestsCount - currentLoadPosition;
        uint64 iterCount = diff > batchSize ? batchSize : diff;

        for (uint i = 0; i < iterCount; i++) {
            Types.DistributorRequest memory request = getRequest(seasonSnapshot, currentLoadPosition);
            requests.push(request);
            for (uint j = 0; j < request.periods.length; j++) {
                uint64 periodId = request.periods[j];
                Types.MaybeUninit storage periodIndex = fairsToPeriodsToSpecialitiesToPeriodIndex[request.fairId][periodId];
                if (!periodIndex.isInited) {
                    continue; // we didn't pass this period in distribution command - skipping unwanted request
                }
                Types.FairPeriod storage period = allPeriods[periodIndex.value];
                period.allRequests.push(request.serviceNumber);
            }
            currentLoadPosition++;
        }
    }

    function distribute() public onlyOrigin {
        require(!isDistributed());

        uint64 batchSize = 500;

        uint64 diff = requestsCount - currentDistributionPosition;
        uint64 iterCount = diff > batchSize ? batchSize : diff;

        for (uint i = 0; i < iterCount; i++) {
            Types.DistributorRequest storage request = requests[currentDistributionPosition]; // 1.1

            for (uint j = 0; j < request.periods.length; j++) {
                uint64 periodId = request.periods[j];
                uint256 userPeriodId = uint256(uint128(request.userId)) << 128 | uint256(periodId); // it's basically a tuple (period, userId)
                Types.MaybeUninit storage periodIndex = fairsToPeriodsToSpecialitiesToPeriodIndex[request.fairId][periodId];
                if (!periodIndex.isInited) {
                    continue; // we didn't pass this period in distribution command - skipping unwanted request
                }
                Types.FairPeriod storage period = allPeriods[periodIndex.value];

                if (period.isRequestFullyProcessed[request.serviceNumber]) {
                    continue;
                }

                if (registeredDeclarantRequests[userPeriodId] != 0 && registeredDeclarantRequests[userPeriodId] != request.serviceNumber) {
                    period.rejectedServiceNumbers.push(request.serviceNumber);
                    period.isRequestFullyProcessed[request.serviceNumber] = true;
                    continue; // skip registered Individuals
                }
                if (period.placesCount > 0) {
                    period.placesCount--;
                    period.serviceNumbers.push(request.serviceNumber); // 1.2
                    registeredDeclarantRequests[userPeriodId] = request.serviceNumber; // 1.3 setting mark that other requests for this declarant should be declined
                    period.isRequestFullyProcessed[request.serviceNumber] = true;  // 1.3 setting mark that request was processed
                }
            }

            currentDistributionPosition++;
        }
    }

    function getUnoccupiedPlaces() public view returns(uint64[] memory, bool[] memory) {
        uint64[] memory result = new uint64[](getPeriodsCount());
        bool[] memory areUpdatable = new bool[](result.length);
        for (uint i = 0; i < result.length; i++) {
            if (allPeriods[i].speciality == Types.Speciality.Vegetables) {
                result[i] = allPeriods[i].placesCount;
                areUpdatable[i] = true;
            }
        }
        return (result, areUpdatable);
    }

    function getRequestedPlaces() public view returns(uint64[] memory) {
        uint64[] memory result = new uint64[](getPeriodsCount());
        for (uint i = 0; i < result.length; i++) {
            if (allPeriods[i].speciality == Types.Speciality.Vegetables) {
                result[i] = uint64(allPeriods[i].allRequests.length);
            }
        }
        return result;
    }

    function getPeriodsCount() public view returns(uint64) {
        return uint64(allPeriods.length);
    }

    function getPeriod(uint64 index) public view returns(uint64, uint64, bytes30[] memory, bytes30[] memory, bytes30[] memory, Types.Speciality) {
        Types.FairPeriod storage period = allPeriods[index];
        return (period.fairId, period.date, period.serviceNumbers, period.waitingList, period.rejectedServiceNumbers, period.speciality);
    }

    function updatePlaces(uint64[] memory placesCounts) public onlyOrigin {
        for (uint i = 0; i < placesCounts.length; i++) {
            if (allPeriods[i].speciality == Types.Speciality.Vegetables) {
                allPeriods[i].placesCount = placesCounts[i];
            }
        }
        currentDistributionPosition = 0;
    }

    function finalizeWaitingLists() public onlyOrigin {
        require(!isWaitingListFinalized);
        for (uint i = 0; i < allPeriods.length; i++) {
            Types.FairPeriod storage period = allPeriods[i];
            for (uint j = 0; j < period.allRequests.length; j++) {
                bytes30 serviceNumber = period.allRequests[j];
                if (!period.isRequestFullyProcessed[serviceNumber]) {
                    period.waitingList.push(serviceNumber);
                }
            }
        }
        isWaitingListFinalized = true;
    }

    function getRequest(SeasonSnapshot seasonSnapshot, uint64 index) private view returns (Types.DistributorRequest memory) {
        (bytes30 serviceNumber, bytes16 userId, Types.DeclarantType declarantType, uint64 fairId, uint64[] memory periods, Types.Speciality speciality) = seasonSnapshot.getIndividualRequest(index);
        return Types.DistributorRequest(serviceNumber, userId, declarantType, fairId, periods, speciality);
    }
}

contract FarmersDistributor is IDistributor {
    address public seasonSnapshotAddress;
    address public userPeriodsStorageAddress;
    uint64 currentLoadPosition;
    uint64 currentDistributionPosition;
    bool isPositionSet;
    bool shouldDeclineRequestsWithLoweredPriority;
    bool public isWaitingListFinalized;
    uint64 public requestsCount;
    Types.DistributorRequest[] requests;
    Types.FairPeriod[] allPeriods;
    mapping(uint64 => mapping(uint256 => bytes30)) fairsToRegisteredDeclarantRequests;
    mapping(uint256 => mapping(uint256 => Types.MaybeUninit)) fairsToPeriodsToSpecialitiesToPeriodIndex;

    constructor(address seasonSnapshotAddress_, address userPeriodsStorageAddress_) public {
        SeasonSnapshot seasonSnapshot = SeasonSnapshot(seasonSnapshotAddress_);
        require(seasonSnapshot.owner() == owner);

        userPeriodsStorageAddress = userPeriodsStorageAddress_;
        seasonSnapshotAddress = seasonSnapshotAddress_;
        requestsCount = seasonSnapshot.getFarmerRequestsCount();
        shouldDeclineRequestsWithLoweredPriority = true;
    }

    function isLoaded() public view returns (bool) {
        return isPositionSet &&
            currentLoadPosition >= requestsCount;
    }

    function isDistributed() public view returns (bool) {
        return isLoaded() &&
            currentDistributionPosition >= requestsCount;
    }

    function init(uint64[] memory fairsIds, uint64[] memory periods, Types.Speciality[] memory specialities, uint64[] memory placesCount) public onlyOrigin {
        for (uint i = 0; i < fairsIds.length; i++) {
            Types.FairPeriod memory fairPeriod;
            fairPeriod.fairId = fairsIds[i];
            fairPeriod.date = periods[i];
            fairPeriod.placesCount = placesCount[i];
            fairPeriod.speciality = specialities[i];
            allPeriods.push(fairPeriod);
            if (specialities[i] == Types.Speciality.Vegetables) {
                 // only vegetables are allowed for farmers
                fairsToPeriodsToSpecialitiesToPeriodIndex[fairPeriod.fairId][fairPeriod.date] = Types.MaybeUninit(true, i);
            }
        }
        isPositionSet = true;
    }

    function loadRequests() public onlyOrigin {
        require(!isLoaded());

        SeasonSnapshot seasonSnapshot = SeasonSnapshot(seasonSnapshotAddress);
        uint64 batchSize = 500;

        uint64 diff = requestsCount - currentLoadPosition;
        uint64 iterCount = diff > batchSize ? batchSize : diff;

        for (uint i = 0; i < iterCount; i++) {
            Types.DistributorRequest memory request = getRequest(seasonSnapshot, currentLoadPosition);
            requests.push(request);

            for (uint j = 0; j < request.periods.length; j++) {
                uint64 periodId = request.periods[j];
                Types.MaybeUninit storage periodIndex = fairsToPeriodsToSpecialitiesToPeriodIndex[request.fairId][periodId];
                if (!periodIndex.isInited) {
                    continue; // we didn't pass this period in distribution command - skipping unwanted request
                }
                Types.FairPeriod storage period = allPeriods[periodIndex.value];
                period.allRequests.push(request.serviceNumber);
            }
            currentLoadPosition++;
        }
    }

    function distribute() public onlyOrigin {
        require(!isDistributed());

        uint64 batchSize = 500;

        uint64 diff = requestsCount - currentDistributionPosition;
        uint64 iterCount = diff > batchSize ? batchSize : diff;

        UserPeriodsStorage userPeriodsStorage = UserPeriodsStorage(userPeriodsStorageAddress);

        for (uint i = 0; i < iterCount; i++) {
            Types.DistributorRequest storage request = requests[currentDistributionPosition]; // 2.1

            for (uint j = 0; j < request.periods.length; j++) {
                uint64 periodId = request.periods[j];
                uint256 userPeriodId = uint256(uint128(request.userId)) << 128 | uint256(periodId); // it's basically a tuple (period, userId)

                if (shouldDeclineRequestsWithLoweredPriority && userPeriodsStorage.declarantRegisteredRequestForPeriod(userPeriodId) != 0) {
                    continue; // skip request with lowered priority
                }

                Types.MaybeUninit storage periodIndex = fairsToPeriodsToSpecialitiesToPeriodIndex[request.fairId][periodId];
                if (!periodIndex.isInited) {
                    continue; // we didn't pass this period in distribution command - skipping unwanted request
                }
                Types.FairPeriod storage period = allPeriods[periodIndex.value];

                if (period.isRequestFullyProcessed[request.serviceNumber]) {
                    continue; // skipping already processed requsets
                }

                if (fairsToRegisteredDeclarantRequests[request.fairId][userPeriodId] != 0 && fairsToRegisteredDeclarantRequests[request.fairId][userPeriodId] != request.serviceNumber) {
                    period.rejectedServiceNumbers.push(request.serviceNumber);
                    period.isRequestFullyProcessed[request.serviceNumber] = true;
                    continue; // skip registered periods
                }
                if (period.placesCount > 0) {
                    period.placesCount--;
                    period.serviceNumbers.push(request.serviceNumber); // 2.2
                    userPeriodsStorage.addDeclarant(userPeriodId, request.serviceNumber); // 2.3 setting mark that other requests for this declarant should be declined
                    fairsToRegisteredDeclarantRequests[request.fairId][userPeriodId] = request.serviceNumber; // 2.3 setting mark that other requests for this declarant should be declined
                    period.isRequestFullyProcessed[request.serviceNumber] = true;  // 2.3 setting mark that request was processed
                }
            }

            currentDistributionPosition++;
        }

        if (isDistributed() && shouldDeclineRequestsWithLoweredPriority) {
            shouldDeclineRequestsWithLoweredPriority = false; // 2.5
            currentDistributionPosition = 0;
        }
    }

    function getUnoccupiedPlaces() public view returns(uint64[] memory, bool[] memory) {
        uint64[] memory result = new uint64[](getPeriodsCount());
        bool[] memory areUpdatable = new bool[](result.length);
        for (uint i = 0; i < result.length; i++) {
            if (allPeriods[i].speciality == Types.Speciality.Vegetables) {
                result[i] = allPeriods[i].placesCount;
                areUpdatable[i] = true;
            }
        }
        return (result, areUpdatable);
    }

    function getRequestedPlaces() public view returns(uint64[] memory) {
        uint64[] memory result = new uint64[](getPeriodsCount());
        for (uint i = 0; i < result.length; i++) {
            if (allPeriods[i].speciality == Types.Speciality.Vegetables) {
                result[i] = uint64(allPeriods[i].allRequests.length);
            }
        }
        return result;
    }

    function getPeriodsCount() public view returns(uint64) {
        return uint64(allPeriods.length);
    }

    function getPeriod(uint64 index) public view returns(uint64, uint64, bytes30[] memory, bytes30[] memory, bytes30[] memory, Types.Speciality) {
        Types.FairPeriod storage period = allPeriods[index];
        return (period.fairId, period.date, period.serviceNumbers, period.waitingList, period.rejectedServiceNumbers, period.speciality);
    }

    function updatePlaces(uint64[] memory placesCounts) public onlyOrigin {
        for (uint i = 0; i < placesCounts.length; i++) {
            if (allPeriods[i].speciality == Types.Speciality.Vegetables) {
                allPeriods[i].placesCount = placesCounts[i];
            }
        }
        currentDistributionPosition = 0;
    }

    function finalizeWaitingLists() public onlyOrigin {
        require(!isWaitingListFinalized);
        for (uint i = 0; i < allPeriods.length; i++) {
            Types.FairPeriod storage period = allPeriods[i];
            for (uint j = 0; j < period.allRequests.length; j++) {
                bytes30 serviceNumber = period.allRequests[j];
                if (!period.isRequestFullyProcessed[serviceNumber]) {
                    period.waitingList.push(serviceNumber);
                }
            }
        }
        isWaitingListFinalized = true;
    }

    function getRequest(SeasonSnapshot seasonSnapshot, uint64 index) private view returns (Types.DistributorRequest memory) {
        (bytes30 serviceNumber, bytes16 userId, Types.DeclarantType declarantType, uint64 fairId, uint64[] memory periods, Types.Speciality speciality) = seasonSnapshot.getFarmerRequest(index);
        return Types.DistributorRequest(serviceNumber, userId, declarantType, fairId, periods, speciality);
    }
}

contract LeDistributor is IDistributor {
    address public seasonSnapshotAddress;
    address public userPeriodsStorageAddress;
    uint64 currentLoadPosition;
    uint64 currentDistributionPosition;
    bool isPositionSet;
    bool shouldDeclineRequestsWithLoweredPriority;
    bool public isWaitingListFinalized;
    uint64 public requestsCount;
    Types.DistributorRequest[] requests;
    Types.FairPeriod[] allPeriods;
    mapping(uint64 => mapping(uint256 => bytes30)) fairsToRegisteredDeclarantRequests;
    mapping(uint256 => mapping(uint256 => mapping(uint256 => Types.MaybeUninit))) fairsToPeriodsToSpecialitiesToPeriodIndex;

    constructor(address seasonSnapshotAddress_, address userPeriodsStorageAddress_) public {
        SeasonSnapshot seasonSnapshot = SeasonSnapshot(seasonSnapshotAddress_);
        require(seasonSnapshot.owner() == owner);

        seasonSnapshotAddress = seasonSnapshotAddress_;
        userPeriodsStorageAddress = userPeriodsStorageAddress_;
        requestsCount = seasonSnapshot.getLeRequestsCount();
        shouldDeclineRequestsWithLoweredPriority = true;
    }

    function isLoaded() public view returns (bool) {
        return isPositionSet &&
            currentLoadPosition >= requestsCount;
    }

    function isDistributed() public view returns (bool) {
        return isLoaded() &&
            currentDistributionPosition >= requestsCount;
    }

    function init(uint64[] memory fairsIds, uint64[] memory periods, Types.Speciality[] memory specialities, uint64[] memory placesCount) public onlyOrigin {
        for (uint i = 0; i < fairsIds.length; i++) {
            Types.FairPeriod memory fairPeriod;
            fairPeriod.fairId = fairsIds[i];
            fairPeriod.date = periods[i];
            fairPeriod.placesCount = placesCount[i];
            fairPeriod.speciality = specialities[i];
            allPeriods.push(fairPeriod);
            fairsToPeriodsToSpecialitiesToPeriodIndex[fairsIds[i]][periods[i]][uint256(specialities[i])] = Types.MaybeUninit(true, i);
        }
        isPositionSet = true;
    }

    function loadRequests() public onlyOrigin {
        require(!isLoaded());

        SeasonSnapshot seasonSnapshot = SeasonSnapshot(seasonSnapshotAddress);
        uint64 batchSize = 500;

        uint64 diff = requestsCount - currentLoadPosition;
        uint64 iterCount = diff > batchSize ? batchSize : diff;

        for (uint i = 0; i < iterCount; i++) {
            Types.DistributorRequest memory request = getRequest(seasonSnapshot, currentLoadPosition);
            requests.push(request);
            Types.Speciality speciality = request.speciality;
            for (uint j = 0; j < request.periods.length; j++) {
                uint64 periodId = request.periods[j];
                Types.MaybeUninit storage periodIndex = fairsToPeriodsToSpecialitiesToPeriodIndex[request.fairId][periodId][uint256(speciality)];
                if (!periodIndex.isInited) {
                    continue; // we didn't pass this period in distribution command - skipping unwanted request
                }
                Types.FairPeriod storage period = allPeriods[periodIndex.value];
                period.allRequests.push(request.serviceNumber);
            }
            currentLoadPosition++;
        }
    }

    function distribute() public onlyOrigin {
        require(!isDistributed());

        uint64 batchSize = 500;

        uint64 diff = requestsCount - currentDistributionPosition;
        uint64 iterCount = diff > batchSize ? batchSize : diff;
        UserPeriodsStorage userPeriodsStorage = UserPeriodsStorage(userPeriodsStorageAddress);

        for (uint i = 0; i < iterCount; i++) {
            Types.DistributorRequest storage request = requests[currentDistributionPosition]; // 1.1
            Types.Speciality speciality = request.speciality;

            for (uint j = 0; j < request.periods.length; j++) {
                uint64 periodId = request.periods[j];
                uint256 userPeriodId = uint256(uint128(request.userId)) << 128 | uint256(periodId); // it's basically a tuple (period, userId)

                if (shouldDeclineRequestsWithLoweredPriority && userPeriodsStorage.declarantRegisteredRequestForPeriod(userPeriodId) != 0) {
                    continue; // skip request with lowered priority
                }

                Types.MaybeUninit storage periodIndex = fairsToPeriodsToSpecialitiesToPeriodIndex[request.fairId][periodId][uint256(speciality)];

                if (!periodIndex.isInited) {
                    continue; // we didn't pass this period in distribution command - skipping unwanted request
                }

                Types.FairPeriod storage period = allPeriods[periodIndex.value];

                if (period.isRequestFullyProcessed[request.serviceNumber]) {
                    continue; // skipping already processed requsets
                }

                if (fairsToRegisteredDeclarantRequests[request.fairId][userPeriodId] != 0 && fairsToRegisteredDeclarantRequests[request.fairId][userPeriodId] != request.serviceNumber) {
                    period.rejectedServiceNumbers.push(request.serviceNumber);
                    period.isRequestFullyProcessed[request.serviceNumber] = true;
                    continue; // skip registered periods
                }
                if (period.placesCount > 0) {
                    period.placesCount--;
                    period.serviceNumbers.push(request.serviceNumber); // 3.2
                    userPeriodsStorage.addDeclarant(userPeriodId, request.serviceNumber);        // 3.3 setting mark that other requests for this declarant should be declined
                    fairsToRegisteredDeclarantRequests[request.fairId][userPeriodId] = request.serviceNumber; // 3.3 setting mark that other requests for this declarant should be declined
                    period.isRequestFullyProcessed[request.serviceNumber] = true;  // 3.3 setting mark that request was processed
                }
            }

            currentDistributionPosition++;
        }

        if (isDistributed() && shouldDeclineRequestsWithLoweredPriority) {
            shouldDeclineRequestsWithLoweredPriority = false;   // 3.5
            currentDistributionPosition = 0;
        }
    }

    function getUnoccupiedPlaces() public view returns(uint64[] memory, bool[] memory) {
        uint64[] memory result = new uint64[](getPeriodsCount());
        bool[] memory areUpdatable = new bool[](result.length);
        for (uint i = 0; i < result.length; i++) {
            if (allPeriods[i].speciality == Types.Speciality.Vegetables) {
                result[i] = allPeriods[i].placesCount;
                areUpdatable[i] = true;
            }
        }
        return (result, areUpdatable);
    }

    function getRequestedPlaces() public view returns(uint64[] memory) {
        uint64[] memory result = new uint64[](getPeriodsCount());
        for (uint i = 0; i < result.length; i++) {
            if (allPeriods[i].speciality == Types.Speciality.Vegetables) {
                result[i] = uint64(allPeriods[i].allRequests.length);
            }
        }
        return result;
    }

    function getPeriodsCount() public view returns(uint64) {
        return uint64(allPeriods.length);
    }

    function getPeriod(uint64 index) public view returns(uint64, uint64, bytes30[] memory, bytes30[] memory, bytes30[] memory, Types.Speciality) {
        Types.FairPeriod storage period = allPeriods[index];
        return (period.fairId, period.date, period.serviceNumbers, period.waitingList, period.rejectedServiceNumbers, period.speciality);
    }

    function updatePlaces(uint64[] memory placesCounts) public onlyOrigin {
        for (uint i = 0; i < placesCounts.length; i++) {
            if (allPeriods[i].speciality == Types.Speciality.Vegetables) {
                allPeriods[i].placesCount = placesCounts[i];
            }
        }
        currentDistributionPosition = 0;
    }

    function finalizeWaitingLists() public onlyOrigin {
        require(!isWaitingListFinalized);
        for (uint i = 0; i < allPeriods.length; i++) {
            Types.FairPeriod storage period = allPeriods[i];
            for (uint j = 0; j < period.allRequests.length; j++) {
                bytes30 serviceNumber = period.allRequests[j];
                if (!period.isRequestFullyProcessed[serviceNumber]) {
                    period.waitingList.push(serviceNumber);
                }
            }
        }
        isWaitingListFinalized = true;
    }

    function getRequest(SeasonSnapshot seasonSnapshot, uint64 index) private view returns (Types.DistributorRequest memory) {
        (bytes30 serviceNumber, bytes16 userId, Types.DeclarantType declarantType, uint64 fairId, uint64[] memory periods, Types.Speciality speciality) = seasonSnapshot.getLeRequest(index);
        return Types.DistributorRequest(serviceNumber, userId, declarantType, fairId, periods, speciality);
    }
}

contract DistributionCommand is Owned {
    uint64[] fairsIds;
    uint64[] periods;
    Types.Speciality[] specialities;
    uint64[] individualsPlacesCount;
    uint64[] farmersPlacesCount;
    uint64[] lePlacesCount;
    uint64[] minPlaces;

    constructor(uint64[] memory fairsIds_,
                         uint64[] memory periods_,
                         Types.Speciality[] memory specialities_,
                         uint64[] memory individualsPlacesCount_,
                         uint64[] memory farmersPlacesCount_,
                         uint64[] memory lePlacesCount_,
                         uint64[] memory minPlaces_) public {
        fairsIds = fairsIds_;
        periods = getPeriodsWithRoundedDate(periods_);
        specialities = specialities_;
        individualsPlacesCount = individualsPlacesCount_;
        farmersPlacesCount = farmersPlacesCount_;
        lePlacesCount = lePlacesCount_;
        minPlaces = minPlaces_;
    }

    function getValues() public view returns (uint64[] memory,
                         uint64[] memory,
                         Types.Speciality[] memory,
                         uint64[] memory,
                         uint64[] memory,
                         uint64[] memory,
                         uint64[] memory) {
        return (fairsIds, periods, specialities, individualsPlacesCount, farmersPlacesCount, lePlacesCount, minPlaces);
    }

    function getPeriodsWithRoundedDate(uint64[] memory originalPeriods) private pure returns(uint64[] memory) {
        uint64[] memory result = new uint64[](originalPeriods.length);
        for (uint i = 0; i < result.length; i++) {
           result[i] = (((originalPeriods[i] / 36000000000)/24)*24)*36000000000;
        }
        return result;
    }
}

contract DistributionManager is Owned {
    address public individualsDistributorAddress;
    address public farmersDistributorAddress;
    address public leDistributorAddress;
    address public distributionCommandAddress;

    bool public isDistributed;
    bool isInitialiyRedistributed;

    uint initStep = 0;

    RedistributionInfo[] redistributionInfos;
    uint64[] minPlaces;

    constructor(address individualsDistributorAddress_, address farmersDistributorAddress_, address leDistributorAddress_, address distributionCommandAddress_) public {
        individualsDistributorAddress = individualsDistributorAddress_;
        farmersDistributorAddress = farmersDistributorAddress_;
        leDistributorAddress = leDistributorAddress_;
        distributionCommandAddress = distributionCommandAddress_;
    }

    function isLoaded() public view returns (bool) {
        (IDistributor individualsDistributor, IDistributor farmersDistributor, IDistributor leDistributor) = getDistributors();
        return individualsDistributor.isLoaded() && farmersDistributor.isLoaded() && leDistributor.isLoaded();
    }

    function isInited() public view returns (bool) {
        return initStep > 3;
    }

    function init() public onlyOrigin {
        require (!isInited(), "Already inited");

        (IDistributor individualsDistributor, IDistributor farmersDistributor, IDistributor leDistributor) = getDistributors();
        DistributionCommand distributionCommand = DistributionCommand(distributionCommandAddress);
        (uint64[] memory fairsIds, uint64[] memory periods, Types.Speciality[] memory specialities, uint64[] memory individualsPlacesCount, uint64[] memory farmersPlacesCount, uint64[] memory lePlacesCount, uint64[] memory minPlaces_) = distributionCommand.getValues();
        if (initStep == 0) {
            individualsDistributor.init(fairsIds, periods, specialities, individualsPlacesCount);
        } else if (initStep == 1) {
            farmersDistributor.init(fairsIds, periods, specialities, farmersPlacesCount);
        } else if (initStep == 2) {
            leDistributor.init(fairsIds, periods, specialities, lePlacesCount);
        } else if (initStep == 3) {
            redistributionInfos.length = periods.length;
            minPlaces = minPlaces_;
        } else {
            require(false, "Unreachable");
        }
        initStep += 1;
    }

    function loadRequests() public onlyOwner {
        require(isInited(), "Is not inited");
        require(!isLoaded(), "Already loaded");

        (IDistributor individualsDistributor, IDistributor farmersDistributor, IDistributor leDistributor) = getDistributors();
        if (!individualsDistributor.isLoaded()) {
            individualsDistributor.loadRequests();
        }
        else if (!farmersDistributor.isLoaded()) {
            farmersDistributor.loadRequests(); 
        }
        else if (!leDistributor.isLoaded()) {
            leDistributor.loadRequests();
        }
    }

    function distribute() public onlyOwner {
        require(isLoaded(), "Is not loaded");
        require(!isDistributed, "Aleady distributed");

        (IDistributor individualsDistributor, IDistributor farmersDistributor, IDistributor leDistributor) = getDistributors();
        if (!isInitialiyRedistributed) {
            performInitialRedistribution(individualsDistributor, farmersDistributor, leDistributor);
            isInitialiyRedistributed = true;
        }
        else if (!individualsDistributor.isDistributed()) {
            individualsDistributor.distribute();
        }
        else if (!farmersDistributor.isDistributed()) {
            farmersDistributor.distribute();
        }
        else if (!leDistributor.isDistributed()) {
            leDistributor.distribute();
        } else {
            bool needsRedistribution = false;

            (uint64[] memory iPlaces, bool[] memory iAreUpdatables) = individualsDistributor.getUnoccupiedPlaces();
            (uint64[] memory fPlaces, bool[] memory fAreUpdatables) = farmersDistributor.getUnoccupiedPlaces();
            (uint64[] memory lePlaces, bool[] memory leAreUpdatables) = leDistributor.getUnoccupiedPlaces();

            for (uint i = 0; i < iPlaces.length; i++) {
                uint64 unoccupiedPlacesCount;
                if (leAreUpdatables[i] && lePlaces[i] > 0) { // 4.1
                    unoccupiedPlacesCount = lePlaces[i];
                    lePlaces[i] = 0;

                    if (redistributionInfos[i].redistributedToIndividualsCount < 2) {
                        iPlaces[i] += unoccupiedPlacesCount;
                        needsRedistribution = true;
                        redistributionInfos[i].redistributedToIndividualsCount += 1;
                    } else if (redistributionInfos[i].redistributedToFarmersCount < 2) {
                        fPlaces[i] += unoccupiedPlacesCount;
                        needsRedistribution = true;
                        redistributionInfos[i].redistributedToFarmersCount += 1;
                    }
                } else if (iAreUpdatables[i] && iPlaces[i] > 0) {  // 4.2
                    unoccupiedPlacesCount = iPlaces[i];
                    iPlaces[i] = 0;

                    if (redistributionInfos[i].redistributedToFarmersCount < 2) {
                        fPlaces[i] += unoccupiedPlacesCount;
                        needsRedistribution = true;
                        redistributionInfos[i].redistributedToFarmersCount += 1;
                    } else if (redistributionInfos[i].redistributedToLEsCount < 2) {
                        lePlaces[i] += unoccupiedPlacesCount;
                        needsRedistribution = true;
                        redistributionInfos[i].redistributedToLEsCount += 1;
                    }
                } else if (fAreUpdatables[i] && fPlaces[i] > 0) { // 4.3
                    unoccupiedPlacesCount = fPlaces[i];
                    fPlaces[i] = 0;

                    if (redistributionInfos[i].redistributedToIndividualsCount < 2) {
                        iPlaces[i] += unoccupiedPlacesCount;
                        needsRedistribution = true;
                        redistributionInfos[i].redistributedToIndividualsCount += 1;
                    } else if (redistributionInfos[i].redistributedToLEsCount < 2) {
                        lePlaces[i] += unoccupiedPlacesCount;
                        needsRedistribution = true;
                        redistributionInfos[i].redistributedToLEsCount += 1;
                    }
                }
            }

            if (needsRedistribution) {
                individualsDistributor.updatePlaces(iPlaces);
                farmersDistributor.updatePlaces(fPlaces);
                leDistributor.updatePlaces(lePlaces);
            }
            else {
                individualsDistributor.finalizeWaitingLists();
                farmersDistributor.finalizeWaitingLists();
                leDistributor.finalizeWaitingLists();
                isDistributed = true;
            }
        }
    }

    function getPeriodsCount() public view returns(uint64) {
        (IDistributor individualsDistributor, IDistributor farmersDistributor, IDistributor leDistributor) = getDistributors();
        uint64 iCount = individualsDistributor.getPeriodsCount();
        uint64 fCount = farmersDistributor.getPeriodsCount();
        uint64 leCount = leDistributor.getPeriodsCount();

        require (iCount == fCount && fCount == leCount);

        return iCount;
    }

    function getIndividualsPeriod(uint64 index) public view returns (uint64, uint64, bytes30[] memory, bytes30[] memory, bytes30[] memory, Types.Speciality) {
        IDistributor distributor = IDistributor(individualsDistributorAddress);
        return distributor.getPeriod(index);
    }

    function getFarmersPeriod(uint64 index) public view returns (uint64, uint64, bytes30[] memory, bytes30[] memory, bytes30[] memory, Types.Speciality) {
        IDistributor distributor = IDistributor(farmersDistributorAddress);
        return distributor.getPeriod(index);
    }

    function getLesPeriod(uint64 index) public view returns (uint64, uint64, bytes30[] memory, bytes30[] memory, bytes30[] memory, Types.Speciality) {
        IDistributor distributor = IDistributor(leDistributorAddress);
        return distributor.getPeriod(index);
    }

    function getMinPlace(uint index) public view returns (uint64) {
        return minPlaces[index];
    }

    function getDistributors() private view returns(IDistributor, IDistributor, IDistributor) {
        IDistributor individualsDistributor = IDistributor(individualsDistributorAddress);
        IDistributor farmersDistributor = IDistributor(farmersDistributorAddress);
        IDistributor leDistributor = IDistributor(leDistributorAddress);
        return (individualsDistributor, farmersDistributor, leDistributor);
    }

    function performInitialRedistribution(IDistributor individualsDistributor, IDistributor farmersDistributor, IDistributor leDistributor) private {
        uint64[] memory fRequestedPlaces = farmersDistributor.getRequestedPlaces();
        uint64[] memory leRequestedPlaces = leDistributor.getRequestedPlaces();

        (uint64[] memory iPlaces, bool[] memory iAreUpdatables) = individualsDistributor.getUnoccupiedPlaces();
        (uint64[] memory fPlaces, ) = farmersDistributor.getUnoccupiedPlaces();
        (uint64[] memory lePlaces, ) = leDistributor.getUnoccupiedPlaces();

        for (uint i = 0; i < iPlaces.length; i++) {
            if (!iAreUpdatables[i]) {
                continue;
            }

            // redistributing unoccupied farmers places, if any
            int fDiff = int(fPlaces[i]) - int(fRequestedPlaces[i]);
            if (fDiff > 0) {
                fPlaces[i] = fRequestedPlaces[i];
                iPlaces[i] += uint64(fDiff);
            }

            // redistributing unoccupied le places, if any
            int leDiff = int(lePlaces[i]) - int(leRequestedPlaces[i]);
            if (leDiff > 0) {
                lePlaces[i] = leRequestedPlaces[i];
                iPlaces[i] += uint64(leDiff);
            }
        }

        individualsDistributor.updatePlaces(iPlaces);
        farmersDistributor.updatePlaces(fPlaces);
        leDistributor.updatePlaces(lePlaces);
    }

    struct RedistributionInfo {
        uint8 redistributedToIndividualsCount;
        uint8 redistributedToFarmersCount;
        uint8 redistributedToLEsCount;
    }
}

contract UserPeriodsStorage is Owned {
    mapping(uint256 => bytes30) public declarantRegisteredRequestForPeriod;

    function addDeclarant(uint256 userPeriodId, bytes30 serviceNumber) public onlyOrigin {
        declarantRegisteredRequestForPeriod[userPeriodId] = serviceNumber;
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

    struct OptionU64 {
        bool hasValue;
        uint64 value;
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
