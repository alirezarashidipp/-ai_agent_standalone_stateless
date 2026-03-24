from typing import Literal
from langgraph.graph import StateGraph, END, START
from state import GroomingSession, GroomingPhase
from nodes import (
    phase0_extractor,
    phase1_lock,
    phase2_tech_lead,
    phase2_ask,
    phase3_synthesize,
    phase3_feedback
)

def route_by_phase(state: GroomingSession) -> Literal[
    "phase0", 
    "phase1", 
    "phase2_init", 
    "phase2_loop", 
    "phase3_init", 
    "phase3_loop", 
    "__end__"
]:
    """
    Deterministic Router: Maps the exact FSM phase to the corresponding computational node.
    """
    phase_map = {
        GroomingPhase.PHASE0_EXTRACT: "phase0",
        GroomingPhase.PHASE1_LOCK: "phase1",
        GroomingPhase.PHASE2_TECH_LEAD: "phase2_init",
        GroomingPhase.PHASE2_ASK: "phase2_loop",
        GroomingPhase.PHASE3_SYNTHESIZE: "phase3_init",
        GroomingPhase.PHASE3_FEEDBACK: "phase3_loop",
        GroomingPhase.DONE: END,
        GroomingPhase.ABORTED: END
    }
    
    return phase_map.get(state.phase, END)

def create_graph():
    workflow = StateGraph(GroomingSession)

    # Register Nodes
    workflow.add_node("phase0", phase0_extractor)
    workflow.add_node("phase1", phase1_lock)
    workflow.add_node("phase2_init", phase2_tech_lead)
    workflow.add_node("phase2_loop", phase2_ask)
    workflow.add_node("phase3_init", phase3_synthesize)
    workflow.add_node("phase3_loop", phase3_feedback)

    # Core Routing Logic
    workflow.add_conditional_edges(START, route_by_phase)

    # Force Stateless Exit
    for node in ["phase0", "phase1", "phase2_init", "phase2_loop", "phase3_init", "phase3_loop"]:
        workflow.add_edge(node, END)

    # Compile without Checkpointer (Zero-Persistence)
    return workflow.compile()

app = create_graph()
