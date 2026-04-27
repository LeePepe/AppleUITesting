import Foundation

struct ToolDefinitions: Sendable {
    func allTools() -> [[String: Any]] {
        [
            getAxTreeTool,
            captureScreenshotTool,
            visionEvalTool,
            performActionTool,
            runFlowTool,
        ]
    }

    private var getAxTreeTool: [String: Any] {
        [
            "name": "get_ax_tree",
            "description": "Get the accessibility tree of the target application. Returns a JSON hierarchy of UI elements with roles, labels, identifiers, and values.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "element_id": [
                        "type": "string",
                        "description": "Optional accessibility identifier to get a specific element instead of the full tree",
                    ]
                ],
                "required": [] as [String],
            ],
        ]
    }

    private var captureScreenshotTool: [String: Any] {
        [
            "name": "capture_screenshot",
            "description": "Capture a screenshot of the target application. Returns a base64-encoded PNG image.",
            "inputSchema": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String],
            ],
        ]
    }

    private var visionEvalTool: [String: Any] {
        [
            "name": "vision_eval",
            "description": "Evaluate a screenshot against visual expectations using Claude Vision. Captures a screenshot and checks if the listed expectations are met.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "expectations": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "List of visual expectations to evaluate (e.g., 'Login button is visible', 'No error banners shown')",
                    ]
                ],
                "required": ["expectations"],
            ],
        ]
    }

    private var performActionTool: [String: Any] {
        [
            "name": "perform_action",
            "description": "Perform a UI action on the target application. Supports tap, tapCoordinate, typeText, swipe, scroll, and longPress.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "action_type": [
                        "type": "string",
                        "enum": ["tap", "tapCoordinate", "typeText", "swipe", "scroll", "longPress"],
                        "description": "The type of action to perform",
                    ],
                    "identifier": [
                        "type": "string",
                        "description": "Accessibility identifier of the target element (for tap, typeText, longPress)",
                    ],
                    "x": [
                        "type": "number",
                        "description": "X coordinate (for tapCoordinate)",
                    ],
                    "y": [
                        "type": "number",
                        "description": "Y coordinate (for tapCoordinate)",
                    ],
                    "text": [
                        "type": "string",
                        "description": "Text to type (for typeText)",
                    ],
                    "direction": [
                        "type": "string",
                        "enum": ["up", "down", "left", "right"],
                        "description": "Direction (for swipe, scroll)",
                    ],
                    "amount": [
                        "type": "number",
                        "description": "Scroll amount in points (for scroll, default 100)",
                    ],
                    "duration": [
                        "type": "number",
                        "description": "Duration in seconds (for longPress, default 1.0)",
                    ],
                ],
                "required": ["action_type"],
            ],
        ]
    }

    private var runFlowTool: [String: Any] {
        [
            "name": "run_flow",
            "description": "Run a sequence of UI actions as a flow. Each step can include an optional delay before execution. Stops on first failure.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "steps": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "action_type": [
                                    "type": "string",
                                    "enum": ["tap", "tapCoordinate", "typeText", "swipe", "scroll", "longPress"],
                                ],
                                "identifier": ["type": "string"],
                                "x": ["type": "number"],
                                "y": ["type": "number"],
                                "text": ["type": "string"],
                                "direction": [
                                    "type": "string",
                                    "enum": ["up", "down", "left", "right"],
                                ],
                                "amount": ["type": "number"],
                                "duration": ["type": "number"],
                                "delay_ms": [
                                    "type": "integer",
                                    "description": "Delay in milliseconds before executing this step",
                                ],
                            ],
                            "required": ["action_type"],
                        ],
                        "description": "Array of action steps to execute in sequence",
                    ]
                ],
                "required": ["steps"],
            ],
        ]
    }
}
