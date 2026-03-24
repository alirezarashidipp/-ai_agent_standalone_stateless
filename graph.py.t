from typing import Literal
from langgraph.graph import StateGraph, END, START
from state import GroomingSession, GroomingPhase
from nodes import (
    extraction_node,
    clarification_node,
    tech_refinement_node,
    ac_review_node,
    final_story_node
)

def route_by_phase(state: GroomingSession) -> Literal[
    "extractor", 
    "clarifier", 
    "tech_lead", 
    "agile_coach", 
    "story_writer", 
    "__end__"
]:
    """
    Stateless Router: Decides which node to execute based on the current phase.
    """
    phase = state.phase

    if phase == GroomingPhase.START:
        return "extractor"
    
    if phase == GroomingPhase.CLARIFYING:
        return "clarifier"
    
    if phase == GroomingPhase.REFINING_TECH:
        return "tech_lead"
    
    if phase == GroomingPhase.REVIEWING_AC:
        return "agile_coach"
    
    if phase == GroomingPhase.FINALIZING:
        return "story_writer"
    
    return END

def create_graph():
    # Initialize the graph with the Pydantic State model
    workflow = StateGraph(GroomingSession)

    # Add Nodes
    workflow.add_node("extractor", extraction_node)
    workflow.add_node("clarifier", clarification_node)
    workflow.add_node("tech_lead", tech_refinement_node)
    workflow.add_node("agile_coach", ac_review_node)
    workflow.add_node("story_writer", final_story_node)

    # Core Logic: Start -> Router
    workflow.add_conditional_edges(START, route_by_phase)

    # Node Transitions
    # After each node, we return to END so the API can send the state to the client
    workflow.add_edge("extractor", END)
    workflow.add_edge("clarifier", END)
    workflow.add_edge("tech_lead", END)
    workflow.add_edge("agile_coach", END)
    workflow.add_edge("story_writer", END)

    # Compile without any checkpointer for true statelessness
    return workflow.compile()

app = create_graph()
