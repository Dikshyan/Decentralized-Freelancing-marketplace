
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title DecentralizedFreelanceMarketplace
 * @dev A smart contract for managing freelance projects and payments
 */
contract DecentralizedFreelanceMarketplace {
    
    struct Project {
        uint256 id;
        address client;
        address freelancer;
        string title;
        string description;
        uint256 budget;
        uint256 deadline;
        bool isCompleted;
        bool isPaid;
        bool isDisputed;
    }
    
    mapping(uint256 => Project) public projects;
    mapping(address => uint256[]) public clientProjects;
    mapping(address => uint256[]) public freelancerProjects;
    
    uint256 public projectCounter;
    uint256 public platformFeePercent = 5; // 5% platform fee
    address public owner;
    
    event ProjectCreated(uint256 indexed projectId, address indexed client, string title, uint256 budget);
    event ProjectAssigned(uint256 indexed projectId, address indexed freelancer);
    event ProjectCompleted(uint256 indexed projectId);
    event PaymentReleased(uint256 indexed projectId, uint256 amount);
    event DisputeRaised(uint256 indexed projectId);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyClient(uint256 _projectId) {
        require(msg.sender == projects[_projectId].client, "Only client can call this function");
        _;
    }
    
    modifier onlyFreelancer(uint256 _projectId) {
        require(msg.sender == projects[_projectId].freelancer, "Only assigned freelancer can call this function");
        _;
    }
    
    modifier projectExists(uint256 _projectId) {
        require(_projectId < projectCounter, "Project does not exist");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Creates a new project and deposits the budget
     * @param _title Project title
     * @param _description Project description
     * @param _deadline Project deadline (timestamp)
     */
    function createProject(
        string memory _title,
        string memory _description,
        uint256 _deadline
    ) external payable {
        require(msg.value > 0, "Budget must be greater than 0");
        require(_deadline > block.timestamp, "Deadline must be in the future");
        require(bytes(_title).length > 0, "Title cannot be empty");
        
        projects[projectCounter] = Project({
            id: projectCounter,
            client: msg.sender,
            freelancer: address(0),
            title: _title,
            description: _description,
            budget: msg.value,
            deadline: _deadline,
            isCompleted: false,
            isPaid: false,
            isDisputed: false
        });
        
        clientProjects[msg.sender].push(projectCounter);
        
        emit ProjectCreated(projectCounter, msg.sender, _title, msg.value);
        projectCounter++;
    }
    
    /**
     * @dev Assigns a freelancer to a project
     * @param _projectId The ID of the project
     * @param _freelancer Address of the freelancer to assign
     */
    function assignFreelancer(uint256 _projectId, address _freelancer) 
        external 
        onlyClient(_projectId) 
        projectExists(_projectId) 
    {
        require(projects[_projectId].freelancer == address(0), "Project already assigned");
        require(_freelancer != address(0), "Invalid freelancer address");
        require(_freelancer != projects[_projectId].client, "Client cannot be freelancer");
        
        projects[_projectId].freelancer = _freelancer;
        freelancerProjects[_freelancer].push(_projectId);
        
        emit ProjectAssigned(_projectId, _freelancer);
    }
    
    /**
     * @dev Marks a project as completed by the freelancer
     * @param _projectId The ID of the project
     */
    function submitWork(uint256 _projectId) 
        external 
        onlyFreelancer(_projectId) 
        projectExists(_projectId) 
    {
        require(!projects[_projectId].isCompleted, "Project already completed");
        require(!projects[_projectId].isDisputed, "Project is under dispute");
        require(projects[_projectId].freelancer != address(0), "No freelancer assigned");
        
        projects[_projectId].isCompleted = true;
        
        emit ProjectCompleted(_projectId);
    }
    
    /**
     * @dev Releases payment to freelancer after project completion
     * @param _projectId The ID of the project
     */
    function releasePayment(uint256 _projectId) 
        external 
        onlyClient(_projectId) 
        projectExists(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(project.isCompleted, "Project not completed yet");
        require(!project.isPaid, "Payment already released");
        require(!project.isDisputed, "Project is under dispute");
        
        uint256 platformFee = (project.budget * platformFeePercent) / 100;
        uint256 freelancerPayment = project.budget - platformFee;
        
        project.isPaid = true;
        
        // Transfer payment to freelancer
        payable(project.freelancer).transfer(freelancerPayment);
        
        // Transfer platform fee to owner
        payable(owner).transfer(platformFee);
        
        emit PaymentReleased(_projectId, freelancerPayment);
    }
    
    /**
     * @dev Raises a dispute for a project (can be called by client or freelancer)
     * @param _projectId The ID of the project
     */
    function raiseDispute(uint256 _projectId) 
        external 
        projectExists(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(
            msg.sender == project.client || msg.sender == project.freelancer,
            "Only client or freelancer can raise dispute"
        );
        require(!project.isPaid, "Cannot dispute after payment");
        require(!project.isDisputed, "Dispute already raised");
        require(project.freelancer != address(0), "No freelancer assigned");
        
        project.isDisputed = true;
        
        emit DisputeRaised(_projectId);
    }
    
    // View functions for getting project details
    function getProject(uint256 _projectId) 
        external 
        view 
        projectExists(_projectId) 
        returns (Project memory) 
    {
        return projects[_projectId];
    }
    
    function getClientProjects(address _client) external view returns (uint256[] memory) {
        return clientProjects[_client];
    }
    
    function getFreelancerProjects(address _freelancer) external view returns (uint256[] memory) {
        return freelancerProjects[_freelancer];
    }
    
    // Admin functions
    function resolveDispute(uint256 _projectId, bool _favorClient) 
        external 
        onlyOwner 
        projectExists(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(project.isDisputed, "No dispute to resolve");
        require(!project.isPaid, "Payment already released");
        
        if (_favorClient) {
            // Refund to client
            payable(project.client).transfer(project.budget);
        } else {
            // Pay freelancer
            uint256 platformFee = (project.budget * platformFeePercent) / 100;
            uint256 freelancerPayment = project.budget - platformFee;
            
            payable(project.freelancer).transfer(freelancerPayment);
            payable(owner).transfer(platformFee);
        }
        
        project.isPaid = true;
        project.isDisputed = false;
    }
    
    function updatePlatformFee(uint256 _newFeePercent) external onlyOwner {
        require(_newFeePercent <= 10, "Fee cannot exceed 10%");
        platformFeePercent = _newFeePercent;
    }
}
