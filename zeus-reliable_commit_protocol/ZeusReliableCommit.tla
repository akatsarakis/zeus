------------------------------- MODULE ZeusReliableCommit -------------------------------
\* This module specifies the reliable commit protocol presented 
\* in the Zeus paper that appears in Eurosys'21.
\* This module includes everything but the pipelining optimization presented in the paper.

\* Model check passed [@ 21st of Jan 2021] with the following parameters:
\*  R_NODES = {0, 1, 2}
\*  R_MAX_EPOCH = 4
\*  R_MAX_VERSION = 4

EXTENDS Integers

CONSTANTS R_NODES,
          R_MAX_EPOCH,
          R_MAX_VERSION
  
VARIABLES rMsgs,
          rKeyState,
          rKeySharers,
          rKeyVersion,
          rKeyRcvedACKs,
          rKeyLastWriter, 
          rNodeEpochID,
          rAliveNodes,
          rEpochID
          
vars == << rMsgs, rKeyState, rKeySharers, rKeyVersion, rKeyRcvedACKs, 
           rKeyLastWriter, rNodeEpochID, rAliveNodes, rEpochID >>
-----------------------------------------------------------------------------
\* The consistent invariant: all alive nodes in valid state should have the same value / TS  
RConsistentInvariant ==
    \A k,s \in rAliveNodes:  \/ rKeyState[k] /= "valid"
                             \/ rKeyState[s] /= "valid" 
                             \/ rKeyVersion[k] = rKeyVersion[s]

RMaxVersionDistanceInvariant == \* this does not hold w/ the pipelining optimization
    \A k,s \in rAliveNodes:
                             \/ rKeyVersion[k] <= rKeyVersion[s] + 1
                             \/ rKeyVersion[s] <= rKeyVersion[k] + 1
 
RSingleOnwerInvariant == 
    \A k,s \in rAliveNodes:
                             \/ rKeySharers[k] /= "owner" 
                             \/ rKeySharers[s] /= "owner" 
                             \/ k = s

ROnwerOnlyWriterInvariant == 
    \A k \in rAliveNodes:
                             \/ rKeyState[k] /= "write" 
                             \/ rKeySharers[k] = "owner" 

ROnwerHighestVersionInvariant ==  \* owner has the highest version among alive nodes
    \A k,s \in rAliveNodes:
                            \/ /\ rKeySharers[s] /= "owner" 
                               /\ rKeySharers[k] /= "owner" 
                            \/ 
                               /\ rKeySharers[k] = "owner"
                               /\ rKeyVersion[k] >= rKeyVersion[s]
                            \/
                               /\ rKeySharers[s] = "owner"
                               /\ rKeyVersion[s] >= rKeyVersion[k]

-----------------------------------------------------------------------------

RMessage ==  \* Messages exchanged by the Protocol   
    [type: {"INV", "ACK"}, sender    : R_NODES,
                           epochID   : 0..R_MAX_EPOCH,
                           version   : 0..R_MAX_VERSION] 
        \union
    [type: {"VAL"},        epochID   : 0..R_MAX_EPOCH,
                           version   : 0..R_MAX_VERSION] 
    
    
RTypeOK ==  \* The type correctness invariant
    /\  rMsgs           \subseteq RMessage
    /\  rAliveNodes     \subseteq R_NODES
    /\  \A n \in R_NODES: rKeyRcvedACKs[n] \subseteq (R_NODES \ {n})
    /\  rNodeEpochID    \in [R_NODES -> 0..R_MAX_EPOCH]
    /\  rKeyLastWriter  \in [R_NODES -> R_NODES]
    /\  rKeyVersion     \in [R_NODES -> 0..R_MAX_VERSION]
    /\  rKeySharers     \in [R_NODES -> {"owner", "reader", "non-sharer"}]
    /\  rKeyState       \in [R_NODES -> {"valid", "invalid", "write", "replay"}]
    

RInit == \* The initial predicate
    /\  rMsgs           = {}
    /\  rEpochID        = 0
    /\  rAliveNodes     = R_NODES
    /\  rKeyVersion     = [n \in R_NODES |-> 0] 
    /\  rNodeEpochID    = [n \in R_NODES |-> 0] 
    /\  rKeyRcvedACKs   = [n \in R_NODES |-> {}]
    /\  rKeySharers     = [n \in R_NODES |-> "reader"] 
    /\  rKeyState       = [n \in R_NODES |-> "valid"]
    /\  rKeyLastWriter  = [n \in R_NODES |-> CHOOSE k \in R_NODES:
                                           \A m \in R_NODES: k <= m]

-----------------------------------------------------------------------------

RNoChanges_in_membership == UNCHANGED <<rAliveNodes, rEpochID>>
    
RNoChanges_but_membership ==
    UNCHANGED <<rMsgs, rKeyState, rKeyVersion, 
                rKeyRcvedACKs, rKeyLastWriter, 
                rKeySharers, rNodeEpochID>>

RNoChanges ==
    /\  RNoChanges_in_membership 
    /\  RNoChanges_but_membership 

-----------------------------------------------------------------------------
\* A buffer maintaining all network messages. Messages are only appended to 
\* this variable (not \* removed once delivered) intentionally to check 
\* protocol's tolerance in dublicates and reorderings 
RSend(m) == rMsgs' = rMsgs \union {m}

\* Check if all acknowledgments for a write have been received                                                  
RAllACKsRcved(n) == (rAliveNodes \ {n}) \subseteq rKeyRcvedACKs[n]

RIsAlive(n) == n \in rAliveNodes 

RNodeFailure(n) == \* Emulate a node failure
\*    Make sure that there are atleast 3 alive nodes before killing a node
    /\ \E k,m \in rAliveNodes: /\ k /= n 
                               /\ m /= n
                               /\ m /= k
    /\ rEpochID' = rEpochID + 1
    /\ rAliveNodes' = rAliveNodes \ {n}
    /\ RNoChanges_but_membership

-----------------------------------------------------------------------------
RNewOwner(n) ==
    /\ \A k \in rAliveNodes: 
       /\ rKeySharers[k]        /= "owner"
       /\ \/ /\  rKeyState[k]    = "valid"    \* all alive replicas are in valid state
             /\  rKeySharers[k]  = "reader"  \* and there is not alive owner
          \/ /\  rKeySharers[k]  = "non-sharer"  \* and there is not alive owner
    /\ rKeySharers'              = [rKeySharers    EXCEPT ![n] = "owner"]
    /\ UNCHANGED <<rMsgs, rKeyState, rKeyVersion, rKeyRcvedACKs, 
                   rKeyLastWriter, rAliveNodes, rNodeEpochID, rEpochID>>
       
ROverthrowOwner(n) ==
    \E k \in rAliveNodes: 
        /\ rKeyState[k]   = "valid"
        /\ rKeySharers[k] = "owner"
        /\ rKeySharers'   = [rKeySharers EXCEPT ![n] = "owner",
                                                ![k] = "reader"]
        /\ UNCHANGED <<rMsgs, rKeyState, rKeyVersion, rKeyRcvedACKs,
                       rKeyLastWriter, rAliveNodes, rNodeEpochID, rEpochID>>

RGetOwnership(n) ==
    /\ rKeySharers[n] /= "owner"
    /\ \A x \in rAliveNodes: rNodeEpochID[x] = rEpochID \*TODO may move this to RNewOwner
    /\ \/  ROverthrowOwner(n) 
       \/  RNewOwner(n)    
-----------------------------------------------------------------------------

RRead(n) ==  \* Execute a read
    /\ rNodeEpochID[n] = rEpochID
    /\ rKeyState[n]    = "valid"
    /\ RNoChanges

RRcvInv(n) ==  \* Process a received invalidation
 \E m \in rMsgs: 
        /\ m.type     = "INV"
        /\ m.epochID  = rEpochID
        /\ m.sender  /= n
        /\ m.sender  \in rAliveNodes
        \* always acknowledge a received invalidation (irrelevant to the timestamp)
        /\ RSend([type       |-> "ACK",
                  epochID    |-> rEpochID,
                  sender     |-> n,   
                  version    |-> m.version])
        /\ \/ m.version        > rKeyVersion[n]
              /\ rKeyState[n]   \in {"valid", "invalid", "replay"}
              /\ rKeyState'      = [rKeyState EXCEPT ![n] = "invalid"]
              /\ rKeyVersion'    = [rKeyVersion EXCEPT ![n]  = m.version]
              /\ rKeyLastWriter' = [rKeyLastWriter EXCEPT ![n] = m.sender]
           \/ m.version         <= rKeyVersion[n]
              /\ UNCHANGED <<rKeyState, rKeyVersion, rKeyLastWriter>>
        /\ UNCHANGED <<rAliveNodes, rKeySharers, rKeyRcvedACKs, rNodeEpochID, rEpochID>>
            
RRcvVal(n) ==   \* Process a received validation
    \E m \in rMsgs: 
        /\ rKeyState[n] /= "valid"
        /\ m.type        = "VAL"
        /\ m.epochID     = rEpochID
        /\ m.version     = rKeyVersion[n]
        /\ rKeyState'    = [rKeyState EXCEPT ![n] = "valid"]
        /\ UNCHANGED <<rMsgs, rKeyVersion, rKeyLastWriter, rKeySharers, 
                       rAliveNodes, rKeyRcvedACKs, rNodeEpochID, rEpochID>>
                       
RReaderActions(n) ==  \* Actions of a write follower
    \/ RRead(n)          
    \/ RRcvInv(n)
    \/ RRcvVal(n) 
    
-------------------------------------------------------------------------------------                       

RWrite(n) ==
    /\  rNodeEpochID[n]   =    rEpochID
    /\  rKeySharers[n]    \in  {"owner"} 
    /\  rKeyState[n]      \in  {"valid"} \* May add invalid state here as well
    /\  rKeyVersion[n]    <    R_MAX_VERSION
    /\  rKeyLastWriter'   =    [rKeyLastWriter  EXCEPT ![n] = n]
    /\  rKeyRcvedACKs'    =    [rKeyRcvedACKs   EXCEPT ![n] = {}]
    /\  rKeyState'        =    [rKeyState       EXCEPT ![n] = "write"]
    /\  rKeyVersion'      =    [rKeyVersion     EXCEPT ![n] = rKeyVersion[n] + 1]
    /\  RSend([type        |-> "INV",
               epochID     |-> rEpochID,
               sender      |-> n,
               version     |-> rKeyVersion[n] + 1])              
    /\ UNCHANGED <<rAliveNodes, rKeySharers, rNodeEpochID, rEpochID>>

RRcvAck(n) ==   \* Process a received acknowledment
    \E m \in rMsgs: 
        /\ m.type         =     "ACK"
        /\ m.epochID      =     rEpochID
        /\ m.sender      /=     n
        /\ m.version      =     rKeyVersion[n]
        /\ m.sender      \notin rKeyRcvedACKs[n]
        /\ rKeyState[n]  \in    {"write", "replay"}
        /\ rKeyRcvedACKs' =     [rKeyRcvedACKs    EXCEPT ![n] = 
                                             rKeyRcvedACKs[n] \union {m.sender}]
        /\ UNCHANGED <<rMsgs, rKeyState, rKeyVersion, rKeyLastWriter, 
                       rAliveNodes, rKeySharers, rNodeEpochID, rEpochID>>

RSendVals(n) == \* Send validations once received acknowledments from all alive nodes
    /\ rKeyState[n]     \in   {"write", "replay"}
    /\ RAllACKsRcved(n)
    /\ rKeyState'         =   [rKeyState EXCEPT![n] = "valid"]
    /\ RSend([type        |-> "VAL", 
              epochID     |-> rEpochID,
              version     |-> rKeyVersion[n]])
    /\ UNCHANGED <<rKeyRcvedACKs, rKeyVersion, rKeyLastWriter, 
                   rAliveNodes, rKeySharers, rNodeEpochID, rEpochID>>

ROwnerActions(n) ==   \* Actions of a read/write coordinator 
    \/ RRead(n)          
    \/ RWrite(n)         
    \/ RRcvAck(n)
    \/ RSendVals(n) 
    
------------------------------------------------------------------------------------- 
    
RWriteReplay(n) == \* Execute a write-replay
    /\  rKeyLastWriter'  =    [rKeyLastWriter   EXCEPT ![n] = n]
    /\  rKeyRcvedACKs'   =    [rKeyRcvedACKs    EXCEPT ![n] = {}]
    /\  rKeyState'       =    [rKeyState        EXCEPT ![n] = "replay"]
    /\  RSend([type       |-> "INV",
               sender     |-> n,
               epochID    |-> rEpochID,
               version    |-> rKeyVersion[n]])
    /\  UNCHANGED <<rKeyVersion, rKeySharers, rAliveNodes, rNodeEpochID, rEpochID>>

RLocalWriteReplay(n) == \* TODO this might not even be necessary
    /\ \/ rKeySharers[n] = "owner" 
       \/ rKeyState[n]   = "replay"
    /\  RWriteReplay(n)
    
RFailedNodeWriteReplay(n) ==
    /\  ~RIsAlive(rKeyLastWriter[n])
    /\  rKeyState[n]     = "invalid"
    /\  RWriteReplay(n)

RUpdateLocalEpochID(n) ==
    /\ rKeyState[n]    = "valid" 
    /\ rNodeEpochID'   = [rNodeEpochID EXCEPT![n] = rEpochID]
    /\ UNCHANGED <<rMsgs, rKeyState, rKeyVersion, rKeyRcvedACKs, 
                   rKeyLastWriter, rKeySharers, rAliveNodes, rEpochID>>

RReplayActions(n) ==
    /\ rNodeEpochID[n] < rEpochID
    /\ \/ RLocalWriteReplay(n)
       \/ RFailedNodeWriteReplay(n)
       \/ RUpdateLocalEpochID(n)
    
------------------------------------------------------------------------------------- 
RNext == \* Modeling protocol (Owner and Reader actions while emulating failures)
    \E n \in rAliveNodes:       
            \/ RReaderActions(n)
            \/ ROwnerActions(n)
            \/ RReplayActions(n)
            \/ RGetOwnership(n)
            \/ RNodeFailure(n) \* emulate node failures


(***************************************************************************)
(* The complete definition of the algorithm                                *)
(***************************************************************************)

Spec == RInit /\ [][RNext]_vars

Invariants == /\ ([]RTypeOK) 
              /\ ([]RConsistentInvariant)
              /\ ([]RSingleOnwerInvariant)
              /\ ([]ROnwerOnlyWriterInvariant)
              /\ ([]RMaxVersionDistanceInvariant)
              /\ ([]ROnwerHighestVersionInvariant)

THEOREM Spec => Invariants
=============================================================================
