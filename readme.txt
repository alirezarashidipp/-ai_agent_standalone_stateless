stateDiagram-v2
    direction TD
    
    [*] --> Phase0_Extract: Raw Input
    
    Phase0_Extract --> Phase1_Lock: Missing Fields (who, what, why)
    Phase0_Extract --> Phase2_TechLead: All Core Fields Extracted
    
    Phase1_Lock --> Phase1_Lock: Human-in-the-Loop (Inject Missing Field)
    Phase1_Lock --> [*]: Abort (Validation failed >= 3 times)
    Phase1_Lock --> Phase2_TechLead: All Core Fields Validated
    
    Phase2_TechLead --> Phase2_AskQuestions: Generates Architect Questions
    
    Phase2_AskQuestions --> Phase2_AskQuestions: Human-in-the-Loop (Answer/Skip Question)
    Phase2_AskQuestions --> Phase3_Synthesize: All Questions Processed
    
    Phase3_Synthesize --> Phase3_Feedback: Drafts Initial Jira Story
    
    Phase3_Feedback --> Phase3_Synthesize: Human-in-the-Loop (Provide Revision Feedback)
    Phase3_Feedback --> [*]: Complete (User Confirms OR Retries >= 3)
