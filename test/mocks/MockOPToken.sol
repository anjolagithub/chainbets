// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockOPToken is ERC20 {
    constructor() ERC20("Mock OP", "MOP") {
        _mint(msg.sender, 100000000 * 10 ** 18); // Significantly larger initial supply
    }

    // Add a mint function for testing purposes
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
