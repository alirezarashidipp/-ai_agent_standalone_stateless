# main.py
import os
import uuid
from typing import Optional, Dict, Any
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel
from langgraph.types import Command
from psycopg_pool import ConnectionPool
from langgraph.checkpoint.postgres import PostgresSaver

# Import the refactored graph compilation function
from graph import get_compiled_graph

# ---------------------------------------------------------
# Configuration & Infrastructure Setup
# ---------------------------------------------------------
# In production, DB_URI must be injected via K8s Secrets
DB_URI = os.getenv("POSTGRES_URI", "postgresql://user:password@localhost:5432/workflow_db")

# Connection pool for checkpointer
pool = ConnectionPool(conninfo=DB_URI, max_size=20, kwargs={"autocommit": True})

app = FastAPI(
    title="Jira Story Generator API",
    description="Stateless orchestration API for Agile Story Generation",
    version="1.0.0"
)

# ---------------------------------------------------------
# Pydantic Schemas for API Requests/Responses
# ---------------------------------------------------------
class StartRequest(BaseModel):
    raw_input: str

class ResumeRequest(BaseModel):
    thread_id: str
    user_response: str

# ---------------------------------------------------------
# Core Execution Engine
# ---------------------------------------------------------
def execute_graph_step(graph: Any, config: Dict, input_data: Any) -> Dict:
    """
    Executes the compiled graph until completion or the next interrupt.
    Returns a standardized JSON payload representing the current state.
    """
    state_update = None
    
    # Stream events until completion or interrupt
    for event in graph.stream(input_data, config=config):
        for node_name, update in event.items():
            # Handle LangGraph v0.2+ '__interrupt__' tuple guardrail
            if not isinstance(update, dict):
                continue
            state_update = update

    # Evaluate final state after this execution step
    if state_update:
        if state_update.get("is_aborted"):
            return {"status": "aborted", "reason": state_update.get("abort_reason")}
            
        if state_update.get("is_complete"):
            return {"status": "completed", "final_story": state_update.get("final_story")}

    # Check snapshot for pending interrupts (Human-in-the-Loop)
    state_snapshot = graph.get_state(config)
    if state_snapshot.next:
        interrupt_val = state_snapshot.tasks[0].interrupts[0].value
        return {
            "status": "pending_input",
            "thread_id": config["configurable"]["thread_id"],
            "prompt": interrupt_val
        }
    
    return {"status": "error", "message": "Unexpected end of execution queue."}

# ---------------------------------------------------------
# API Endpoints
# ---------------------------------------------------------
@app.post("/workflow/start", status_code=status.HTTP_200_OK)
def start_workflow(req: StartRequest):
    if not req.raw_input.strip():
        raise HTTPException(status_code=400, detail="raw_input cannot be empty.")
        
    thread_id = str(uuid.uuid4())
    config = {"configurable": {"thread_id": thread_id}}
    
    # Strict initialization of TypedDict
    initial_state = {
        "raw_input": req.raw_input,
        "who": None, "what": None, "why": None, "ac_evidence": None,
        "missing_fields": [], "current_field_target": None,
        "phase1_retries": 0, "last_rejection_reason": None,
        "is_aborted": False, "abort_reason": None,
        "pending_questions": [], "current_question": None, "tech_notes": [],
        "final_story": None, "feedback_retries": 0,
        "is_complete": False, "feedback_raw": ""
    }

    # Context Manager ensures safe DB connection handling per request
    with PostgresSaver(pool) as checkpointer:
        # Checkpointer creates required tables automatically in setup()
        checkpointer.setup() 
        graph = get_compiled_graph(checkpointer=checkpointer)
        return execute_graph_step(graph, config, initial_state)

@app.post("/workflow/resume", status_code=status.HTTP_200_OK)
def resume_workflow(req: ResumeRequest):
    if not req.thread_id.strip() or not req.user_response.strip():
        raise HTTPException(status_code=400, detail="thread_id and user_response are required.")

    config = {"configurable": {"thread_id": req.thread_id}}
    
    with PostgresSaver(pool) as checkpointer:
        graph = get_compiled_graph(checkpointer=checkpointer)
        
        # Validate thread existence and pending state
        state_snapshot = graph.get_state(config)
        if not state_snapshot.next:
            raise HTTPException(
                status_code=400, 
                detail="Workflow thread not found or is not in a pending state."
            )
            
        # Resume execution using the Command API
        resume_command = Command(resume=req.user_response)
        return execute_graph_step(graph, config, resume_command)

# ---------------------------------------------------------
# Server Lifecycle
# ---------------------------------------------------------
@app.on_event("shutdown")
def shutdown_event():
    # Graceful shutdown of DB connection pool
    pool.close()
