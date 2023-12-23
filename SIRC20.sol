// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SIRC20 is ReentrancyGuard {
    mapping(string => uint) public max;
    mapping(string => uint) public lim;
    mapping(string => uint) public minted;
    mapping(string => mapping(address => uint)) public balance;

    event Deploy(string indexed tick, uint max, uint lim);
    event Mint(string indexed tick, address indexed to, uint amt);
    event Transfer(string indexed tick, address indexed from, address indexed to, uint amt);

    struct Listing {
        string tick;
        address from;
        uint amt;
        uint price;
        bool partialAllowed;
    }
    mapping(uint => Listing) public listed;
    uint public nextListId;

    event List(uint indexed id, string indexed tick, address indexed from, uint amt, uint price, bool partialAllowed);
    event Unlist(uint indexed id, string indexed tick, address indexed from);
    event Buy(uint indexed id, string indexed tick, address from, address indexed to, uint amt, uint price, uint fee);

    string public constant REWARD_TICK = "sirc";

    address public contributor;
    uint public contributorRewardPct = 100; // 1%

    constructor() {
        contributor = msg.sender;
        max[REWARD_TICK] = 21_000_000 ether;
    }

    function reward(address to) private {
        if (minted[REWARD_TICK] == 21_000_000 ether) return;
        minted[REWARD_TICK] += 1 ether;
        balance[REWARD_TICK][to] += 1 ether;
        emit Mint(REWARD_TICK, to, 1 ether);
    }

    function validTick(string memory tick) public pure {
        require(bytes(tick).length == 4, "SIRC20: tick must be 4 characters");
        for (uint i = 0; i < 4; i++) {
            bytes1 b = bytes(tick)[i];
            require((b >= 0x30 && b <= 0x39) || (b >= 0x61 && b <= 0x7a), "SIRC20: tick must be lowercase and number");
        }
    }

    function deploy(string memory tick, uint _max, uint _lim) external {
        validTick(tick);
        require(max[tick] == 0, "SIRC20: already deployed");
        require(_max > 0, "SIRC20: max must be positive");
        require(_lim > 0, "SIRC20: lim must be positive");
        require(_lim <= _max, "SIRC20: lim must be less than or equal to max");
        max[tick] = _max;
        lim[tick] = _lim;
        emit Deploy(tick, _max, _lim);
        reward(msg.sender);
    }

    function mint(string memory tick, uint amt) external {
        require(max[tick] > 0, "SIRC20: not deployed");
        require(minted[tick] + amt <= max[tick], "SIRC20: max exceeded");
        require(amt <= lim[tick], "SIRC20: lim exceeded");
        minted[tick] += amt;
        balance[tick][msg.sender] += amt;
        emit Mint(tick, msg.sender, amt);
        reward(msg.sender);
    }

    function transfer(string memory tick, address to, uint amt) external {
        require(max[tick] > 0, "SIRC20: not deployed");
        require(balance[tick][msg.sender] >= amt, "SIRC20: insufficient balance");
        balance[tick][msg.sender] -= amt;
        balance[tick][to] += amt;
        emit Transfer(tick, msg.sender, to, amt);
    }

    function airdrop(string memory tick, address[] memory to, uint[] memory amt) external {
        require(max[tick] > 0, "SIRC20: not deployed");
        require(to.length == amt.length, "SIRC20: to and amt length mismatch");
        uint total;
        for (uint i = 0; i < to.length; i++) {
            total += amt[i];
        }
        require(balance[tick][msg.sender] >= total, "SIRC20: insufficient balance");
        for (uint i = 0; i < to.length; i++) {
            balance[tick][msg.sender] -= amt[i];
            balance[tick][to[i]] += amt[i];
            emit Transfer(tick, msg.sender, to[i], amt[i]);
        }
    }

    function list(string memory tick, uint amt, uint price, bool partialAllowed) external {
        require(max[tick] > 0, "SIRC20: not deployed");
        require(amt > 0, "SIRC20: amt must be positive");
        require(price > 0, "SIRC20: price must be positive");
        require(balance[tick][msg.sender] >= amt, "SIRC20: insufficient balance");
        balance[tick][msg.sender] -= amt;
        listed[nextListId] = Listing(tick, msg.sender, amt, price, partialAllowed);
        emit List(nextListId, tick, msg.sender, amt, price, partialAllowed);
        nextListId++;
        reward(msg.sender);
    }

    function unlist(uint id) external {
        Listing memory listing = listed[id];
        require(listing.from == msg.sender, "SIRC20: not owner");
        require(listing.amt > 0, "SIRC20: not listed");
        balance[listing.tick][msg.sender] += listing.amt;
        listed[id].amt = 0;
        emit Unlist(id, listing.tick, msg.sender);
    }

    function buy(uint id) external payable nonReentrant {
        Listing memory listing = listed[id];
        require(listing.amt > 0, "SIRC20: not listed");
        require(msg.value == listing.price, "SIRC20: incorrect price");
        uint fee = (msg.value * contributorRewardPct) / 10000;
        balance[listing.tick][msg.sender] += listing.amt;
        listed[id].amt = 0;
        payable(contributor).transfer(fee);
        payable(listing.from).transfer(msg.value - fee);
        emit Buy(id, listing.tick, listing.from, msg.sender, listing.amt, listing.price, fee);
        reward(msg.sender);
    }

    function buyPartial(uint id, uint amt) external payable nonReentrant {
        Listing memory listing = listed[id];
        require(listing.amt > 0, "SIRC20: not listed");
        require(listing.partialAllowed, "SIRC20: partial not allowed");
        require(amt > 0, "SIRC20: amt must be positive");
        require(amt <= listing.amt, "SIRC20: amt must be less than or equal to listing amt");
        require(msg.value == (listing.price * amt) / listing.amt, "SIRC20: incorrect price");
        uint fee = (msg.value * contributorRewardPct) / 10000;
        balance[listing.tick][msg.sender] += amt;
        listed[id].amt -= amt;
        payable(contributor).transfer(fee);
        payable(listing.from).transfer(msg.value - fee);
        emit Buy(id, listing.tick, listing.from, msg.sender, amt, listing.price, fee);
        reward(msg.sender);
    }

    modifier onlyContributor() {
        require(msg.sender == contributor, "SIRC20: not contributor");
        _;
    }

    function setContributor(address _contributor) external onlyContributor {
        contributor = _contributor;
    }

    function setContributorRewardPct(uint _contributorRewardPct) external onlyContributor {
        require(_contributorRewardPct <= 10000, "SIRC20: contributor reward pct must be less than or equal to 10000");
        contributorRewardPct = _contributorRewardPct;
    }
}
