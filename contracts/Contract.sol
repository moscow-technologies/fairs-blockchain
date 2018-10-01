pragma solidity ^0.4.24;

contract Owned {
    address public owner;

    constructor() public {
        owner = tx.origin;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function isDeployed() public pure returns (bool) {
        return true;
    }
}

contract SeasonFactory is Owned {
    address[] public seasons;
    address public newVersionAddress;

    event SeasonCreated(uint64 indexed begin, uint64 indexed end, address season);

    function migrateToNewVersion(address newVersionAddress_) public onlyOwner {
        require(newVersionAddress == 0);
        require(newVersionAddress_ != address(this));

        SeasonFactory newVersion = SeasonFactory(newVersionAddress_);
        require(newVersion.owner() == owner);
        require(newVersion.isDeployed());

        newVersionAddress = newVersionAddress_;
    }

    function addSeason(address season) public onlyOwner {
        if (newVersionAddress != 0) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            newVersion.addSeason(season);
            return;
        }

        SeasonShim seasonShim = SeasonShim(season);
        require(seasonShim.owner() == owner);
        require(seasons.length == 0 || SeasonShim(seasons[seasons.length - 1]).end() < seasonShim.begin());

        seasons.push(seasonShim);
        emit SeasonCreated(seasonShim.begin(), seasonShim.end(), season);
    }

    function getSeasonsCount() public view returns (uint64) {
        if (newVersionAddress != 0) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            return newVersion.getSeasonsCount();
        }

        return uint64(seasons.length);
    }

    function getSeasonForDate(uint64 date) public view returns (address) {
        if (newVersionAddress != 0) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            return newVersion.getSeasonForDate(date);
        }

        for (uint64 i = uint64(seasons.length) - 1; i >= 0; i--) {
            SeasonShim season = SeasonShim(seasons[i]);
            if (date >= season.begin() && date <= season.end())
                return season;
        }
        return 0;
    }

    function getLastSeason() public view returns (address) {
        if (newVersionAddress != 0) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            return newVersion.getLastSeason();
        }

        if (seasons.length == 0) {
            return 0;
        }

        return seasons[seasons.length - 1];
    }
}

contract SeasonShim is Owned {
    uint64 public begin;
    uint64 public end;

    function getHistoricalIndices() public view returns (uint64[]) {
        return new uint64[](0);
    }

    function getRequestByIndex(uint64) public view returns (bytes30, uint64, Types.DeclarantType, string, uint64, uint8[], uint64, uint64, string, uint64[], bytes16) {
        return (0, 0, Types.DeclarantType.Individual, "", 0, new uint8[](0), 0, 0, "", new uint64[](0), 0);
    }

    function getStatusUpdates(bytes30) public view returns (uint64[], uint64[], string) {
        return (new uint64[](0), new uint64[](0), "");
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

    constructor(uint64 begin_, uint64 end_, string name_) public {
        begin = begin_;
        end = end_;
        name = name_;
    }

    function createRequest(bytes30 serviceNumber, uint64 date, Types.DeclarantType declarantType, string declarantName, uint64 fairId, uint8[] assortment, uint64 district, uint64 region, string details, uint64[] periods, bytes16 userId) public onlyOwner {
        require(getRequestIndex(serviceNumber) < 0, "Request with provided service number already exists");

        nodes.length++;
        uint64 newlyInsertedIndex = getRequestsCount() - 1;

        Request storage request = nodes[newlyInsertedIndex].request;
        request.serviceNumber = serviceNumber;
        request.date = date;
        request.declarantType = declarantType;
        request.declarantName = declarantName;
        request.fairId = fairId;
        request.district = district;
        request.region = region;
        request.assortment = assortment;
        request.details = details;
        request.periods = periods;
        request.userId = userId;
        request.statusUpdates.push(Types.StatusUpdate(date, 1010, ""));
        requestServiceNumberToIndex[request.serviceNumber] = newlyInsertedIndex;

        fixPlacementInHistory(newlyInsertedIndex, date);

        emit RequestCreated(serviceNumber, newlyInsertedIndex);
    }

    function fixPlacementInHistory(uint64 newlyInsertedIndex, uint64 date) private onlyOwner {
        if (newlyInsertedIndex == 0) {
            nodes[0].prev = - 1;
            nodes[0].next = - 1;
            return;
        }

        int index = tailIndex;
        while (index >= 0) {
            Node storage n = nodes[uint64(index)];
            if (n.request.date <= date) {
                break;
            }
            index = n.prev;
        }

        if (index < 0) {
            nodes[headIndex].prev = newlyInsertedIndex;
            nodes[newlyInsertedIndex].next = headIndex;
            nodes[newlyInsertedIndex].prev = - 1;
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

    function updateStatus(bytes30 serviceNumber, uint64 responseDate, uint64 statusCode, string note) public onlyOwner {
        int index = getRequestIndex(serviceNumber);

        require(index >= 0, "Request with provided service number was not found");

        Request storage request = nodes[uint64(index)].request;
        for (uint64 i = 0; i < request.statusUpdates.length; i++) {
            Types.StatusUpdate storage update = request.statusUpdates[i];
            require(
                update.responseDate != responseDate
                || update.statusCode != statusCode
            || !(bytes(update.note).length == bytes(note).length && containsString(update.note, note))
            );
        }

        request.statusUpdates.push(Types.StatusUpdate(responseDate, statusCode, note));
        request.statusUpdatesNotes = strConcat(request.statusUpdatesNotes, "\x1f", note);
    }

    function getSeasonDetails() public view returns (uint64, uint64, string) {
        return (begin, end, name);
    }

    function getAllServiceNumbers() public view returns (bytes30[]) {
        bytes30[] memory result = new bytes30[](getRequestsCount());
        for (uint64 i = 0; i < result.length; i++) {
            result[i] = nodes[i].request.serviceNumber;
        }
        return result;
    }

    function getHistoricalIndices() public view returns (uint64[]){
        uint64[] memory result = new uint64[](getRequestsCount());
        uint64 tookCount = 0;
        int currentIndex = headIndex;
        for (uint64 i = 0; i < nodes.length && tookCount < result.length; i++) {
            Node storage node = nodes[uint64(currentIndex)];
            if (hasDisitributableStatus(node.request.statusUpdates)) {
                result[tookCount++] = uint64(currentIndex);
            }
            currentIndex = node.next;
        }

        uint64[] memory trimmedResult = new uint64[](tookCount);
        for (uint64 j = 0; j < trimmedResult.length; j++) {
            trimmedResult[j] = result[j];
        }
        return trimmedResult;
    }

    function hasDisitributableStatus(Types.StatusUpdate[] statusUpdates) private pure returns (bool) {
        uint latestStatusIndex = 0;
        for (uint i = 1; i < statusUpdates.length; i++) {
            if (statusUpdates[latestStatusIndex].responseDate <= statusUpdates[i].responseDate) {
                latestStatusIndex = i;
            }
        }
        uint64 latestStatus = statusUpdates[latestStatusIndex].statusCode;
        return latestStatus == 1040 || latestStatus == 1050;
    }

    function getRequestIndex(bytes30 serviceNumber) public view returns (int) {
        uint64 index = requestServiceNumberToIndex[serviceNumber];

        if (index == 0 && (nodes.length == 0 || nodes[0].request.serviceNumber != serviceNumber)) {
            return - 1;
        }

        return int(index);
    }

    function getRequestByServiceNumber(bytes30 serviceNumber) public view returns (bytes30, uint64, Types.DeclarantType, string, uint64, uint8[], uint64, uint64, string, uint64[], bytes16) {
        int index = getRequestIndex(serviceNumber);

        if (index < 0) {
            return (0, 0, Types.DeclarantType.Individual, "", 0, new uint8[](0), 0, 0, "", new uint64[](0), 0);
        }

        return getRequestByIndex(uint64(index));
    }

    function getRequestByIndex(uint64 index) public view returns (bytes30, uint64, Types.DeclarantType, string, uint64, uint8[], uint64, uint64, string, uint64[], bytes16) {
        Request storage request = nodes[index].request;
        return (request.serviceNumber, request.date, request.declarantType, request.declarantName, request.fairId, request.assortment, request.district, request.region, request.details, request.periods, request.userId);
    }

    function getRequestsCount() public view returns (uint64) {
        return uint64(nodes.length);
    }

    function getStatusUpdates(bytes30 serviceNumber) public view returns (uint64[], uint64[], string) {
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

    function getMatchingRequests(uint64 skipCount, uint64 takeCount, Types.DeclarantType[] declarantTypes, string declarantName, uint64 fairId, uint8[] assortment, uint64 district) public view returns (uint64[]) {
        uint64[] memory result = new uint64[](takeCount);
        uint64 skippedCount = 0;
        uint64 tookCount = 0;
        int currentIndex = headIndex;
        for (uint64 i = 0; i < nodes.length && tookCount < result.length; i++) {
            Node storage node = nodes[uint64(currentIndex)];
            if (isMatch(node.request, declarantTypes, declarantName, fairId, assortment, district)) {
                if (skippedCount < skipCount) {
                    skippedCount++;
                }
                else {
                    result[tookCount++] = uint64(currentIndex);
                }
            }
            currentIndex = node.next;
        }

        uint64[] memory trimmedResult = new uint64[](tookCount);
        for (uint64 j = 0; j < trimmedResult.length; j++) {
            trimmedResult[j] = result[j];
        }
        return trimmedResult;
    }

    function isMatch(Request request, Types.DeclarantType[] declarantTypes, string declarantName_, uint64 fairId_, uint8[] assortment_, uint64 district_) private pure returns (bool) {
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
        if (assortment_.length > 0) {
            for (uint64 i = 0; i < assortment_.length; i++) {
                if (contains(request.assortment, assortment_[i])) {
                    return true;
                }
            }
            return false;
        }
        return true;
    }

    function contains(uint8[] array, uint8 value) private pure returns (bool) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == value)
                return true;
        }
        return false;
    }

    function containsDeclarant(Types.DeclarantType[] array, Types.DeclarantType value) private pure returns (bool) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == value)
                return true;
        }
        return false;
    }

    function isEmpty(string value) private pure returns (bool) {
        return bytes(value).length == 0;
    }

    function containsString(string _base, string _value) internal pure returns (bool) {
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

    function strConcat(string a, string b, string c) private pure returns (string) {
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
        Types.DeclarantType declarantType;
        string declarantName;
        uint64 fairId;
        uint8[] assortment;
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
}
