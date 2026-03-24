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
    Stateless Router: Determines the entry node based on the current phase.
    This is the core of the 'Resume' capability in K8s without a database.
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
    # Initialize the graph with the stateless Pydantic State
    workflow = StateGraph(GroomingSession)

    # 1. Register Nodes
    workflow.add_node("extractor", extraction_node)
    workflow.add_node("clarifier", clarification_node)
    workflow.add_node("tech_lead", tech_refinement_node)
    workflow.add_node("agile_coach", ac_review_node)
    workflow.add_node("story_writer", final_story_node)

    # 2. Add Conditional Entry Point (The Stateless Jump)
    # The graph always starts here and jumps to the correct node based on 'phase'
    workflow.add_conditional_edges(START, route_by_phase)

    # 3. Add Edges to END
    # Every node MUST return to END so the API can send the updated state back to the client
    workflow.add_edge("extractor", END)
    workflow.add_edge("clarifier", END)
    workflow.add_edge("tech_lead", END)
    workflow.add_edge("agile_coach", END)
    workflow.add_edge("story_writer", END)

    # CRITICAL: Compilation without any checkpointer/persistence
    # This ensures true statelessness for production environments
    return workflow.compile()

# Singleton instance of the graph
app = create_graph()
