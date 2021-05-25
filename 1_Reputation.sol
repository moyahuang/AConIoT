
// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
pragma experimental ABIEncoderV2;

contract Reputation {
    address public owner;
    Factors public factors;

    struct BehaviorRecord {
        uint behaviorID;
        string behavior;
        uint time;
        uint currentWeight;
        bool isLegal;
    }

    struct Factors {
        // 正常访问权重: 
        // 1： 访问
        uint[3] alpha;
        // 异常行为权重: 
        // 1. 过期访问；2. 频繁访问；3：禁用访问（应用层实现验证）
        uint[3] beta;
        uint[2] lamda;

        uint CrBase;
        uint win;
    }

    // 每个实体都有一个行为列表
    struct Behaviors {
        BehaviorRecord[] behaviors;
        uint iLastIdx; // 上一个异常行为的序号 从1开始
        uint CrP;
        uint CrN;
    }

    mapping(address => Behaviors) internal behaviorsHashTable;

    constructor() {
        owner = msg.sender;
        initFactors();
    }

    function initFactors() internal{
        factors.alpha[0] = 1; // 访问
        // factors.alpha[1] = 1; // 代理
        // factors.alpha[2] = 1; // 撤销

        factors.beta[0] = 1; // 频繁
        factors.beta[1] = 1; // 禁用期访问

        factors.lamda[0] = 1; // 正信用分系数
        factors.lamda[1] = 1; // 负信用分系数

        factors.CrBase = 60; // 固定
        factors.win = 5;
    }

    function updateFactors(string memory _key, uint _index, uint _value) public {
        require(
            msg.sender == owner,
            "Error: only owner can update environment factors."
        );
        if(stringCompare(_key, "alpha")) {
            factors.alpha[_index] = _value;
        }
        if(stringCompare(_key, "beta")) {
            factors.beta[_index] = _value;
        }
        if(stringCompare(_key, "win")) {
            factors.win = _value; 
        }
    }
    
    // 访问行为上报
    function reportBehavior(
        address _subject, 
        bool _isLegal, 
        uint256 _behaviorID, 
        string memory _behavior,
        uint _time
    ) public returns(uint credit){
        uint curWeight=0;
        if(_isLegal) {
            curWeight = factors.alpha[_behaviorID];
        } else {
            curWeight = factors.beta[_behaviorID];
        }
        behaviorsHashTable[_subject].behaviors.push(BehaviorRecord(_behaviorID, _behavior, _time, curWeight, _isLegal));

        uint len = behaviorsHashTable[_subject].behaviors.length;
        uint win = factors.win;
        if(_isLegal) {
            uint CrP = 0;
            
            uint temp=0;
            if(len>=win) {
                temp=len-win;
            }
            for(uint i = len-1; i>temp && i>0; i--) {
                if(behaviorsHashTable[_subject].behaviors[i].isLegal) {
                    CrP = CrP + behaviorsHashTable[_subject].behaviors[i].currentWeight;
                }
            }
            behaviorsHashTable[_subject].CrP=CrP;

        } else {
            uint curCrN = behaviorsHashTable[_subject].CrN;
            curCrN = curCrN + (factors.beta[_behaviorID]*(len-behaviorsHashTable[_subject].iLastIdx));
            behaviorsHashTable[_subject].iLastIdx = len;
            behaviorsHashTable[_subject].CrN=curCrN;
        }
        uint curCr = factors.CrBase + 
            factors.lamda[0] * behaviorsHashTable[_subject].CrP -
            factors.lamda[1] * behaviorsHashTable[_subject].CrN;

        return curCr;
    }

    function getLastKBehavior(address _subject, uint k) public view
        returns (BehaviorRecord[] memory) 
    {   
        BehaviorRecord[] memory records = new BehaviorRecord[](k);

        require(behaviorsHashTable[_subject].behaviors.length > k, "Error: There are no enough records!");
        uint len = behaviorsHashTable[_subject].behaviors.length;
        for(uint i = len-1; i > len-k && i>=0; i--) {
            records[i] = BehaviorRecord(
                behaviorsHashTable[_subject].behaviors[i].behaviorID,
                behaviorsHashTable[_subject].behaviors[i].behavior,
                behaviorsHashTable[_subject].behaviors[i].time,
                behaviorsHashTable[_subject].behaviors[i].currentWeight,
                behaviorsHashTable[_subject].behaviors[i].isLegal
            );
        }

        return records;
    }

    function stringCompare(string memory a, string memory b) internal pure returns (bool) {
        if (bytes(a).length != bytes(b).length) {
            return false;
        } else {
            return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
        }
    }


}