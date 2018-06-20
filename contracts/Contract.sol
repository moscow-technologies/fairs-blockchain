pragma solidity ^0.4.23;

contract Owned {
    address public owner;
    
    constructor() public { 
        owner = tx.origin;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function isDeployed() public pure returns(bool) {
        return true;
    }
}

contract SeasonFactory is Owned {    
    address[] public seasons;
    address public newVersionAddress;

    event SeasonCreated(uint64 indexed begin, uint64 indexed end, address season);

    function migrateToNewVersion(address newVersionAddress_) public onlyOwner {
        require (newVersionAddress == 0);

        SeasonFactory newVersion = SeasonFactory(newVersionAddress_);
        require (newVersion.owner() == owner);
        require (newVersion.isDeployed());

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

    function getSeasonsCount() public view returns(uint64) {
        if (newVersionAddress != 0) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            return newVersion.getSeasonsCount(); 
        }

        return uint64(seasons.length);
    }
    
    function getSeasonForDate(uint64 date) public view returns(address) {
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

    function getLastSeason() public view returns(address) {
        if (newVersionAddress != 0) {
            SeasonFactory newVersion = SeasonFactory(newVersionAddress);
            return newVersion.getLastSeason(); 
        }

        return seasons[seasons.length - 1];
    }
}

contract SeasonShim is Owned {
    uint64 public begin;
    uint64 public end;
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

    function createRequest(bytes30 serviceNumber, uint64 date, DeclarantType declarantType, string declarantName, uint64 fairId, uint64[] assortment, uint64 district, uint64 region, string details, uint64 statusCode, string note) public onlyOwner {     
        require (getRequestIndex(serviceNumber) < 0, "Request with provided service number already exists");

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
        request.statusUpdates.push(StatusUpdate(date, statusCode, note));                      
        requestServiceNumberToIndex[request.serviceNumber] = newlyInsertedIndex;
                
        fixPlacementInHistory(newlyInsertedIndex, date);
        
        emit RequestCreated(serviceNumber, newlyInsertedIndex);
    }

    function fixPlacementInHistory(uint64 newlyInsertedIndex, uint64 date) private onlyOwner {
        if (newlyInsertedIndex == 0) {
            nodes[0].prev = -1;
            nodes[0].next = -1;
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

        require (index >= 0, "Request with provided service number was not found");

        Request storage request = nodes[uint64(index)].request;
        request.statusUpdates.push(StatusUpdate(responseDate, statusCode, note));
    }

    function getSeasonDetails() public view returns(uint64, uint64, string) {
        return (begin, end, name);
    }

    function getAllServiceNumbers() public view returns(bytes30[]) {
	    bytes30[] memory result = new bytes30[](getRequestsCount());
	    for (uint64 i = 0; i < result.length; i++) {
		    result[i] = nodes[i].request.serviceNumber;
	    }
	    return result;
    }

    function getRequestIndex(bytes30 serviceNumber) public view returns(int) {
        uint64 index = requestServiceNumberToIndex[serviceNumber];

        if (index == 0 && (nodes.length == 0 || nodes[0].request.serviceNumber != serviceNumber)) {        
            return -1;
        }

        return int(index);
    }

    function getRequestByServiceNumber(bytes30 serviceNumber) public view returns(bytes30, uint64, DeclarantType, string, uint64, uint64[], uint64, uint64, string) {
        int index = getRequestIndex(serviceNumber);

        if (index < 0) {
            return (0, 0, DeclarantType.Individual, "", 0, new uint64[](0), 0, 0, "");
        }
            
        return getRequestByIndex(uint64(index));
    }

    function getRequestByIndex(uint64 index) public view returns(bytes30, uint64, DeclarantType, string, uint64, uint64[], uint64, uint64, string) {
        Request storage request = nodes[index].request;
        bytes30 serviceNumber = request.serviceNumber;
        string memory declarantName = request.declarantName;
        uint64[] memory assortment = getAssortment(request);
        string memory details = request.details;
        return (serviceNumber, request.date, request.declarantType, declarantName, request.fairId, assortment, request.district, request.region, details);
    }

    function getAssortment(Request request) private pure returns(uint64[]) {
        uint64[] memory memoryAssortment = new uint64[](request.assortment.length);
        for (uint64 i = 0; i < request.assortment.length; i++) {
            memoryAssortment[i] = request.assortment[i];
        }
        return memoryAssortment;
    }

    function getRequestsCount() public view returns(uint64) {
        return uint64(nodes.length);
    }

    function getStatusUpdates(bytes30 serviceNumber) public view returns(uint64[], uint64[], string) {
        int index = getRequestIndex(serviceNumber);

        if (index < 0) {
            return (new uint64[](0), new uint64[](0), "");
        }

        Request storage request = nodes[uint64(index)].request;
        uint64[] memory dates = new uint64[](request.statusUpdates.length);
        uint64[] memory statusCodes = new uint64[](request.statusUpdates.length);
        string memory notes = "";
        string memory separator = new string(1);
        bytes memory separatorBytes = bytes(separator);
        separatorBytes[0] = 0x1F;
        separator = string(separatorBytes);
        for (uint64 i = 0; i < request.statusUpdates.length; i++) {
            dates[i] = request.statusUpdates[i].responseDate;
            statusCodes[i] = request.statusUpdates[i].statusCode;
            notes = strConcat(notes, separator, request.statusUpdates[i].note);
        }

        return (dates, statusCodes, notes);
    }

    function getMatchingRequests(uint64 skipCount, uint64 takeCount, DeclarantType[] declarantTypes, string declarantName, uint64 fairId, uint64[] assortment, uint64 district) public view returns(uint64[]) {
        uint64[] memory result = new uint64[](takeCount);
        uint64 skippedCount = 0;
        uint64 tookCount = 0;
        int currentIndex = headIndex;
        for (uint64 j = 0; j < nodes.length && tookCount < result.length; j++) {
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
        for (uint64 k = 0; k < trimmedResult.length; k++) {
            trimmedResult[k] = result[k];
        }
        return trimmedResult;
    }

    function isMatch(Request request, DeclarantType[] declarantTypes, string declarantName_, uint64 fairId_, uint64[] assortment_, uint64 district_) private pure returns(bool) {
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

    function contains(uint64[] array, uint64 value) private pure returns (bool) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == value)
                return true;
        }    
        return false;
    }

    function containsDeclarant(DeclarantType[] array, DeclarantType value) private pure returns (bool) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == value)
                return true;
        }    
        return false;
    }

    function isEmpty(string value) private pure returns(bool) {
        return bytes(value).length == 0;
    }

    function containsString(string _base, string _value) internal pure returns (bool) {
        bytes memory _baseBytes = bytes(_base);
        bytes memory _valueBytes = bytes(_value);

        if (_baseBytes.length < _valueBytes.length) {
            return false;
        }

        for(uint j = 0; j <= _baseBytes.length - _valueBytes.length; j++) {  
            uint i = 0;
            for(; i < _valueBytes.length; i++) {
                if (_baseBytes[i + j] != _valueBytes[i]) {
                    break;
                }
            }

            if (i == _valueBytes.length)
                return true;
        }

        return false;
    }

    function strConcat(string _a, string _b, string _c) private pure returns (string){
        bytes memory _ba = bytes(_a);
        bytes memory _bb = bytes(_b);
        bytes memory _bc = bytes(_c);
        string memory abcde = new string(_ba.length + _bb.length + _bc.length);
        bytes memory babcde = bytes(abcde);
        uint k = 0;
        for (uint i = 0; i < _ba.length; i++) babcde[k++] = _ba[i];
        for (i = 0; i < _bb.length; i++) babcde[k++] = _bb[i];
        for (i = 0; i < _bc.length; i++) babcde[k++] = _bc[i];
        return string(babcde);
    }

    struct Node {
        Request request;
        int prev;
        int next;
    }
 
    struct Request {
        bytes30 serviceNumber;
        uint64 date;
        DeclarantType  declarantType;
        string declarantName;
        uint64 fairId;
        uint64[] assortment;
        uint64 district; // округ
        uint64 region; // район
        StatusUpdate[] statusUpdates;
        string details;
    }

    enum DeclarantType {
        Individual, // ФЛ
        IndividualEntrepreneur, // ИП
        LegalEntity, // ЮЛ
        IndividualAsIndividualEntrepreneur // ФЛ как ЮЛ
    }

    struct StatusUpdate {
        uint64 responseDate;
        uint64 statusCode;
        string note;
    }
}
