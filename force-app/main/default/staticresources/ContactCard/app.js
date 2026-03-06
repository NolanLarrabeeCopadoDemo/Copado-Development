// Contact Card Application
(function() {
    'use strict';
    
    // DOM Elements
    const updateBtn = document.getElementById('update-btn');
    const toggleBtn = document.getElementById('toggle-btn');
    const statusElement = document.getElementById('contact-status');
    const messageElement = document.getElementById('message');
    
    // Contact data
    let contactData = {
        name: 'John Doe',
        email: 'john.doe@example.com',
        phone: '(555) 123-4567',
        status: 'Active'
    };
    
    // Initialize
    function init() {
        updateBtn.addEventListener('click', handleUpdate);
        toggleBtn.addEventListener('click', handleToggleStatus);
        console.log('Contact Card initialized');
    }
    
    // Update contact information
    function handleUpdate() {
        // Simulate update with random data
        const names = ['Jane Smith', 'Bob Johnson', 'Alice Williams', 'John Doe'];
        const randomName = names[Math.floor(Math.random() * names.length)];
        
        contactData.name = randomName;
        contactData.email = randomName.toLowerCase().replace(' ', '.') + '@example.com';
        contactData.phone = generatePhoneNumber();
        
        updateDisplay();
        showMessage('Contact information updated successfully!', 'success');
    }
    
    // Toggle contact status
    function handleToggleStatus() {
        if (contactData.status === 'Active') {
            contactData.status = 'Inactive';
            statusElement.classList.remove('active');
            statusElement.classList.add('inactive');
        } else {
            contactData.status = 'Active';
            statusElement.classList.remove('inactive');
            statusElement.classList.add('active');
        }
        
        statusElement.textContent = contactData.status;
        showMessage('Status changed to ' + contactData.status, 'info');
    }
    
    // Update display with current data
    function updateDisplay() {
        document.getElementById('contact-name').textContent = contactData.name;
        document.getElementById('contact-email').textContent = contactData.email;
        document.getElementById('contact-phone').textContent = contactData.phone;
    }
    
    // Show message to user
    function showMessage(text, type) {
        messageElement.textContent = text;
        messageElement.className = 'message show ' + type;
        
        // Hide message after 3 seconds
        setTimeout(function() {
            messageElement.classList.remove('show');
        }, 3000);
    }
    
    // Generate random phone number
    function generatePhoneNumber() {
        const areaCode = Math.floor(Math.random() * 900) + 100;
        const prefix = Math.floor(Math.random() * 900) + 100;
        const lineNumber = Math.floor(Math.random() * 9000) + 1000;
        return '(' + areaCode + ') ' + prefix + '-' + lineNumber;
    }
    
    // Run initialization when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();