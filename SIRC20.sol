// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SIRC20 is ReentrancyGuard {
    mapping(bytes32 => uint) public max;
    mapping(bytes32 => uint) public lim;
    mapping(bytes32 => uint) public minted;
    mapping(bytes32 => mapping(address => uint)) public balance;

    event Deploy(bytes32 indexed tick, address indexed deployer, uint max, uint lim);
    event Mint(bytes32 indexed tick, address indexed minter, address indexed to, uint amt);
    event Transfer(bytes32 indexed tick, address indexed from, address indexed to, uint amt);

    struct Listing {
        bytes32 tick;
        address from;
        uint amt;
        uint price;
        bool partialAllowed;
    }
    mapping(uint => Listing) public listed;
    uint public nextListId;

    event List(uint indexed id, bytes32 indexed tick, address indexed from, uint amt, uint price, bool partialAllowed);
    event Delist(uint indexed id, bytes32 indexed tick, address indexed from, uint amt);
    event Buy(
        uint indexed id,
        bytes32 indexed tick,
        address from,
        address indexed to,
        uint amt,
        uint price,
        uint fee,
        bool buyPartial
    );

    bytes32 public constant REWARD_TICK = "sirc";

    address public contributor;
    uint public contributorRewardPct = 100; // 1%

    constructor() {
        contributor = msg.sender;
        max[REWARD_TICK] = 21_000_000;
    }

    function reward(address to) private {
        if (minted[REWARD_TICK] == 21_000_000) return;
        minted[REWARD_TICK] += 1;
        balance[REWARD_TICK][to] += 1;
        emit Mint(REWARD_TICK, address(0), to, 1);
    }

    function validTick(bytes32 tick) public pure {
        for (uint i = 0; i < 4; i++) {
            bytes1 char = tick[i];
            bool isLowercaseLetter = (char >= 0x61 && char <= 0x7A); // 'a'-'z'
            bool isNumber = (char >= 0x30 && char <= 0x39); // '0'-'9'
            require(isLowercaseLetter || isNumber, "SIRC20: tick must be lowercase and number");
        }
        for (uint i = 4; i < 32; i++) {
            require(tick[i] == 0, "SIRC20: tick must be 4 characters");
        }
    }

    function deploy(bytes32 tick, uint _max, uint _lim) external {
        validTick(tick);
        require(max[tick] == 0, "SIRC20: already deployed");
        require(_max > 0, "SIRC20: max must be positive");
        require(_lim > 0, "SIRC20: lim must be positive");
        require(_lim <= _max, "SIRC20: lim must be less than or equal to max");
        max[tick] = _max;
        lim[tick] = _lim;
        emit Deploy(tick, msg.sender, _max, _lim);
        reward(msg.sender);
    }

    function mint(bytes32 tick, uint amt) external {
        require(max[tick] > 0, "SIRC20: not deployed");
        require(minted[tick] + amt <= max[tick], "SIRC20: max exceeded");
        require(amt <= lim[tick], "SIRC20: lim exceeded");
        minted[tick] += amt;
        balance[tick][msg.sender] += amt;
        emit Mint(tick, msg.sender, msg.sender, amt);
        reward(msg.sender);
    }

    function transfer(bytes32 tick, address to, uint amt) external {
        require(max[tick] > 0, "SIRC20: not deployed");
        require(balance[tick][msg.sender] >= amt, "SIRC20: insufficient balance");
        balance[tick][msg.sender] -= amt;
        balance[tick][to] += amt;
        emit Transfer(tick, msg.sender, to, amt);
    }

    function airdrop(bytes32 tick, address[] memory to, uint[] memory amt) external {
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

    function list(bytes32 tick, uint amt, uint price, bool partialAllowed) external {
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

    function delist(uint id) external {
        Listing memory listing = listed[id];
        require(listing.from == msg.sender, "SIRC20: not owner");
        require(listing.amt > 0, "SIRC20: not listed");
        balance[listing.tick][msg.sender] += listing.amt;
        listed[id].amt = 0;
        emit Delist(id, listing.tick, msg.sender, listing.amt);
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
        emit Buy(id, listing.tick, listing.from, msg.sender, listing.amt, listing.price, fee, false);
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
        emit Buy(id, listing.tick, listing.from, msg.sender, amt, listing.price, fee, true);
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
