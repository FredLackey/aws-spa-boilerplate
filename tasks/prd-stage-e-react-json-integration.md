# Product Requirements Document: Stage E React JSON Integration

## Introduction/Overview

This PRD outlines the modifications required to the React application located in `apps/hello-world-json/` to integrate with the Lambda API developed in Stage C. The application needs to call the `/api` endpoint, display the JSON response in a formatted manner, and handle loading and error states appropriately. This modified application will serve as the final demonstration of the complete AWS SPA boilerplate stack, showing successful integration between CloudFront, React SPA, and Lambda API.

The current application is a clone of the `apps/hello-world-react/` app and needs to be transformed from a static demonstration into a dynamic application that consumes and displays API data.

## Goals

1. **API Integration**: Successfully call the Lambda API endpoint at `/api` route and receive JSON response
2. **JSON Display**: Present the API response as formatted JSON in the designated green area of the UI
3. **Loading State Management**: Show appropriate loading indicators during API calls
4. **Error Handling**: Display clear error messages when API calls fail or timeout
5. **Completion Messaging**: Update UI text to reflect successful completion of all boilerplate stages
6. **Preserve UI Structure**: Maintain existing React app layout and styling while adding new functionality

## User Stories

1. **As a developer**, I want to see a loading message when the page loads so that I know the API call is in progress.

2. **As a developer**, I want to see the JSON response from the Lambda API displayed in a readable format so that I can verify the full-stack integration is working.

3. **As a developer**, I want to see clear error messages if the API call fails so that I can troubleshoot any deployment issues.

4. **As a developer**, I want the UI to reflect that I've completed all stages of the boilerplate so that I understand this is the final demonstration.

5. **As a developer**, I want the JSON to be displayed in a monospace font with preserved structure so that I can easily read the API response format.

## Functional Requirements

### 1. API Integration
- The application must call the `/api` endpoint using a GET request when the component mounts
- The API endpoint URL must be relative (`/api`) to use the same domain as the React app
- The API call must be implemented using React's `useEffect` hook with an empty dependency array to trigger on mount
- The application must implement a 30-second timeout for API requests

### 2. State Management
- Implement three distinct states using React's `useState`:
  - **Loading state**: Initial state when API call is in progress
  - **Success state**: When API responds with valid JSON data
  - **Error state**: When API call fails, times out, or returns invalid response

### 3. Loading Display
- Display "Loading..." message in the green area while API call is in progress
- Loading message must appear immediately when component mounts
- Loading state must be replaced when API call completes (success or failure)

### 4. Success Display
- Display the complete JSON response from the Lambda API in the green area
- JSON must be formatted with preserved structure (similar to `<pre>` tag behavior)
- Use monospace font family for JSON display
- Display all three expected fields from Lambda response: `title`, `message`, and `date`
- JSON should be properly indented and readable

### 5. Error Handling
- Display error message in the green area when API call fails
- Include HTTP status code if available
- Include error message from response if available
- Provide generic fallback message for network or timeout errors
- Timeout after 30 seconds with appropriate error message

### 6. UI Text Updates
- Change page title from "Stage D Complete!" to "All Stages Complete!"
- Remove any references to "Ready for Stage E" or proceeding to next stages
- Replace green area content with JSON display functionality (loading/success/error states)
- Update completion message to indicate: "If you can read the JSON object above, you have successfully completed the entire stack"
- Update descriptive text to reference successful full-stack integration validation

### 7. JSON Formatting Requirements
- Use `JSON.stringify()` with proper indentation (2 spaces)
- Wrap JSON display in element with monospace font family
- Preserve line breaks and spacing in JSON structure
- Ensure JSON display is contained within the green area styling

## Non-Goals (Out of Scope)

- **API Endpoint Configuration**: No environment variable configuration or build-time API URL setting
- **Advanced Error Recovery**: No retry mechanisms or sophisticated error handling
- **Loading Animations**: No spinners, progress bars, or animated loading indicators
- **JSON Syntax Highlighting**: No color coding or syntax highlighting for JSON display
- **Responsive JSON Display**: No special handling for mobile or small screen JSON formatting
- **API Authentication**: No authentication headers or security tokens
- **Multiple API Calls**: Only one API call on component mount, no refresh or polling
- **Component Refactoring**: No extraction of logic into separate components or custom hooks
- **Advanced State Management**: No Redux, Context API, or external state management libraries
- **Performance Optimization**: No memoization, lazy loading, or performance enhancements
- **Deployment**: No actual deployment or infrastructure changes in this scope

## Design Considerations

### Green Area Styling
- Maintain existing green area styling: `backgroundColor: '#1e5631', border: '1px solid #28a745', color: 'white'`
- Ensure monospace font is readable against dark green background
- Consider using `font-family: 'Courier New', Courier, monospace` for JSON display
- Maintain padding and border radius from existing styling

### Content States
The green area will display one of three content types:
1. **Loading**: Simple text message "Loading..."
2. **Success**: Formatted JSON response in monospace font
3. **Error**: Error message with details when available

### Text Updates
- Replace "Ready for Stage E" heading with "Full-Stack Integration Complete"
- Update paragraph text to reference successful API integration
- Maintain existing styling and layout structure

## Technical Considerations

### React Implementation
- Use `fetch()` API for HTTP requests (no additional dependencies)
- Implement proper cleanup in `useEffect` to handle component unmounting
- Use `AbortController` for request timeout implementation
- Handle JSON parsing errors gracefully

### Error Scenarios to Handle
- Network connectivity issues
- API endpoint not available (404)
- Server errors (5xx status codes)
- Invalid JSON response
- Request timeout (30 seconds)
- CORS issues (though these should be handled by Lambda)

### Browser Compatibility
- Use modern fetch API (supported in target browsers)
- Use standard React hooks (no experimental features)
- Ensure JSON display works across major browsers

## Success Metrics

### Functional Success
- **API Call Success**: Application successfully calls `/api` endpoint and receives response
- **JSON Display**: Lambda response is properly formatted and displayed in green area
- **Loading State**: Loading message appears and disappears appropriately
- **Error Handling**: Error states display appropriate messages for different failure scenarios
- **UI Updates**: All text references correctly reflect completion status

### User Experience Success
- **Fast Loading**: Loading state appears immediately on page load
- **Clear Feedback**: Users can easily distinguish between loading, success, and error states
- **Readable JSON**: API response is clearly formatted and easy to read
- **Appropriate Messaging**: UI text accurately reflects the application's purpose and status

### Technical Success
- **Clean Code**: Implementation follows React best practices
- **No Console Errors**: No JavaScript errors or warnings in browser console
- **Proper State Management**: State transitions work correctly between loading/success/error
- **Timeout Handling**: 30-second timeout properly triggers error state

## Implementation Clarifications

### JSON Response Handling
- **No Validation Required**: Display any valid JSON response received from the API without field validation
- **Pretty Print Format**: Format JSON output similar to console.log() pretty printing for readability
- **Simple Display**: Show the raw JSON structure as received from the Lambda function

### Error Message Strategy
- **Specific Error Details**: Provide clear, specific error messages when possible rather than generic fallbacks
- **Timeout Messaging**: Use "Request timed out after 30 seconds" for timeout scenarios
- **HTTP Status Codes**: Include actual status codes and response messages when available
- **Network Errors**: Provide descriptive messages for connectivity issues

### Environment Considerations
- **Universal Application**: Same error verbosity for all environments (development/production)
- **Developer-Focused**: Application serves as a validation tool for developers setting up AWS environments
- **Placeholder Purpose**: This is a proof-of-concept application, not a production-ready system

### JSON Display Scope
- **Small Response Size**: Lambda response will always be small (title, message, date fields)
- **No Special Handling**: No scrolling, truncation, or size management needed
- **Simple Formatting**: Basic monospace display with proper indentation sufficient

## Stage E Preparation Context

**Important Note**: This PRD represents the **preparatory phase** for Stage E development. The modifications outlined here are designed to prepare the React application UI for the actual Stage E infrastructure deployment and configuration work that follows.

### Preparatory Scope
- **UI Preparation**: Modify the React app to be ready for Stage E deployment
- **API Integration Setup**: Implement the client-side logic to consume the Lambda API
- **Validation Foundation**: Create the application structure needed to validate full-stack integration
- **Pre-Deployment Work**: Complete all React app changes before Stage E infrastructure deployment begins

### Next Phase Context
After completing this PRD's requirements, the development team will proceed to:
1. **Stage E Infrastructure**: Deploy the modified React app through CloudFront with API routing
2. **CloudFront Configuration**: Set up `/api` route behaviors to proxy to Lambda function
3. **End-to-End Testing**: Validate complete integration between React app, CloudFront, and Lambda
4. **Final Validation**: Confirm the entire AWS SPA boilerplate stack is functional

This application modification is **Step 1** of Stage E, focusing solely on preparing the React application code before infrastructure deployment and configuration. 