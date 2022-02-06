//SPDX-License-Identifier: AGPLv3
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import { ConstantFlowAgreementV1 } from "@superfluid-finance/ethereum-contracts/contracts/agreements/ConstantFlowAgreementV1.sol";

import { SuperAppBase } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./LegCFA.sol";

contract BCFA {
    address public _address_a = address(0);
    address public _address_b = address(0);
    ERC20 public _dai;
    int96 public _flowRate;
    bool public _direction;
    uint256 public _lastRefresh = 0;

    // superfluid params
    ConstantFlowAgreementV1 private _cfa_a1;    // A to BCFA
    ConstantFlowAgreementV1 private _cfa_a2;    // BCFA to A
    ConstantFlowAgreementV1 private _cfa_b1;    // B to BCFA
    ConstantFlowAgreementV1 private _cfa_b2;    // BCFA to B

    ISuperToken public _token;

    constructor(
        ConstantFlowAgreementV1 cfa,
        ISuperToken token,
        ERC20 dai,
        address receiver
    ) 
    public {
        // Check addresses
        require(address(cfa) != address(0));
        require(address(token) != address(0));

        // BCFA starts by being the receiver of a CFA
        require(address(receiver) == address(this));

        _address_a = msg.sender;
        _address_b = address(0);

        _cfa_a1 = cfa;
        _cfa_a2 = address(0);
        _cfa_b1 = address(0);
        _cfa_b2 = address(0);

        _token = token;
        _dai = dai;
    
        // Alice must open a CFA to the BCFA
        //  - how does the BCFA acknowledge that it has received a flow?

        // BCFA confirms Alice has done this and routes a CFA back

        // Create a new flow back to Alice at the same flow rate
        (,_flow_rate,,) = _cfa_a1.getFlow(token, _address_a, address(this));
        _cfa_a2 = new ConstantFlowAgreementV1();
        _cfa_a2.createFlow(token, _address_a, _flowRate, "");
    }

    function addLeg(
        CosntantFlowAgreementV1 cfa,
        ISuperToken token,
        ERC20 dai,
        address receiver
    )
    public {
        // Can only call once
        require(_address_b == address(0), "BCFA already initialized!");
        require(msg.sender != address_a, "BCFA initialized with the same address");
        _address_b = msg.sender;

        // Check addresses
        require(address(cfa) != address(0));
        require(address(token) != address(0));
        _cfa_b1 = cfa;

        // BCFA starts by being the receiver of a CFA
        require(address(receiver) == address(this));

        // Dai + flowRate must match the initial leg
        require(_dai == dai);
        (,flowRate,,) = _cfa_b1.getFlow(token, _address_b, address(this));
        require(_flowRate == flowRate);

        // Create a new flow back to Bob at the same flow rate
        _cfa_b2 = new ConstantFlowAgreementV1();
        _cfa_b2.createFlow(token, _address_b, _flowRate, "");

        flipCoin();
    }

    function validateState() public {
        // Check node A
        require(_address_a != address(0));
        require(_cfa_a1 != address(0));
        require(_cfa_a2 != address(0));
        // TODO: confirm state == solvent

        // Check node B
        require(_address_a != address(0));
        require(_cfa_b1 != address(0));
        require(_cfa_b2 != address(0));
        // TODO: confirm state == solvent
    }

    function getFlowRateA() public view returns (int96 flowRate) {
        int96 flowRate;
        (,flowRate,,) = _cfa_a2.getFlow(_token, address(this), _address_a);
    }

    function getFlowRateB() public view returns (int96 flowRate) {
        int96 flowRate;
        (,flowRate,,) = _cfa_b2.getFlow(_token, address(this), _address_b);
    }

    function netFlowRate() public view returns (int96 flowRate) {
        flowRate = getFlowRateA() - getFlowRateB();
    }

    function isFlowingToA() public view returns (bool flowing) {
        bool flowing = netFlowRate() > 0;
    }

    function isFlowingToB() public view returns (bool flowing) {
        bool flowing = netFlowRate() < 0;
    }

    function _flowToA() private {
        // if not already flowing to A2, update the flow rate
        if (netFlowRate() <= 0) {
            // downgrade B2 flow rate
            _cfa_b2.updateFlow(_token, _address_b, 1, "");
            // upgrade A2 flow rate
            _cfa_a2.updateFlow(_token, _address_a, (2 * _flowRate) - 1, "");

            // TODO: emit newFlowDirection
        }
    }

    function _flowToB() private {
        // update both flows if 
        if (netFlowRate() >= 0) {
            // downgrade A2 flow rate
            _cfa_a2.updateFlow(_token, _address_a, 1, "");
            // upgrade B2 flow rate
            _cfa_b2.updateFlow(_token, _address_b, (2 * _flowRate) - 1, "");

            // TODO: emit newFlowDirection
        }
    }

    /**
        BCFA.flipCoin() is the core method that changes the state of the
        bi-directional flow based on pseudo-random boolean value.

        As a proof of concept, the pseudo-random boolean value is used in place
        of a realtime market index. With a realtime market index, Alice and Bob
        make a bet in which Alice receives Bob's flow when the market index
        is above pre-determined level and vice versa for Bob when the market
        index is below that level. 

        This method must be invoked in a transaction costing gas. There is a
        natural incentive for Blice to spend gas to trigger this call when the
        index is above the pre-determined level and vice versa for Bob.

        In a future implementation, this smart contract would retrieve market
        index data from an on-chain oracle and include an additional variable in
        the constructor to specify the strike level.
     */
    function flipCoin() public {
        require(msg.sender == _address_a || msg.sender == _address_b);
        validateState();

        // If >=1 hour since last refresh, flip coin
        uint256 elapsedTime = block.timestamp - _lastRefresh;
        require(elapsedTime >= 1 hours);

        // Get a pseudo-random boolean value
        bool result = bool(uint(keccak256(block.difficulty, block.timestamp)) % 1);
        if (result) {
            _flowToA();
        } else {
            _flowToB();
        }
    }
}
