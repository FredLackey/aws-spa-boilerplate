## Relevant Files

- `apps/hello-world-json/src/App.jsx` - Main React component that needs API integration, state management, and UI updates
- `apps/hello-world-json/src/App.css` - Styling file that may need updates for monospace JSON display
- `apps/hello-world-json/package.json` - Project dependencies (should already have React and Vite)

### Notes

- This is a preparatory task for Stage E infrastructure deployment
- No new dependencies should be added - use built-in fetch API and React hooks
- The application should work in development mode before Stage E deployment
- Focus on client-side changes only - no infrastructure or deployment tasks included

## Tasks

- [ ] 1.0 Implement API State Management
  - [ ] 1.1 Import useEffect hook from React (add to existing useState import)
  - [ ] 1.2 Create apiData state variable using useState (initial value: null)
  - [ ] 1.3 Create loading state variable using useState (initial value: true)
  - [ ] 1.4 Create error state variable using useState (initial value: null)
- [ ] 2.0 Add API Integration with useEffect Hook
  - [ ] 2.1 Create useEffect hook with empty dependency array to trigger on component mount
  - [ ] 2.2 Create AbortController for request timeout handling
  - [ ] 2.3 Implement fetch request to '/api' endpoint with GET method
  - [ ] 2.4 Set 30-second timeout using setTimeout and AbortController
  - [ ] 2.5 Add cleanup function to abort request if component unmounts
- [ ] 3.0 Create Dynamic Content Display for Green Area
  - [ ] 3.1 Replace static green area content with conditional rendering based on state
  - [ ] 3.2 Implement loading state display: show "Loading..." message
  - [ ] 3.3 Implement success state display: show formatted JSON with monospace font
  - [ ] 3.4 Implement error state display: show error message with details
  - [ ] 3.5 Add CSS styling for monospace JSON display (font-family: 'Courier New', Courier, monospace)
- [ ] 4.0 Update UI Text and Messaging
  - [ ] 4.1 Change page title from "✅ Stage D Complete!" to "✅ All Stages Complete!"
  - [ ] 4.2 Update main description text to reference full-stack integration validation
  - [ ] 4.3 Replace green area heading from "Ready for Stage E" to "Full-Stack Integration Complete"
  - [ ] 4.4 Add completion message: "If you can read the JSON object above, you have successfully completed the entire stack"
  - [ ] 4.5 Update bottom description from "Static React application" to reference API integration
- [ ] 5.0 Implement Error Handling and Timeout Logic
  - [ ] 5.1 Add response.ok check for HTTP status validation
  - [ ] 5.2 Implement JSON parsing with try-catch for invalid response handling
  - [ ] 5.3 Create timeout error handling (30 seconds) with specific "Request timed out after 30 seconds" message
  - [ ] 5.4 Handle network errors with descriptive messages
  - [ ] 5.5 Include HTTP status codes and response messages in error display when available
  - [ ] 5.6 Implement proper state updates for success/error scenarios in useEffect 