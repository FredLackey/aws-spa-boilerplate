import { useState, useEffect } from 'react'
import reactLogo from './assets/react.svg'
import viteLogo from '/vite.svg'
import './App.css'

function App() {
  const [count, setCount] = useState(0)
  const [apiData, setApiData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    const controller = new AbortController()
    
    const fetchData = async () => {
      try {
        const timeoutId = setTimeout(() => {
          controller.abort()
        }, 30000) // 30 second timeout
        
        const response = await fetch('/api/', {
          method: 'GET',
          signal: controller.signal
        })
        
        clearTimeout(timeoutId)
        
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}: ${response.statusText}`)
        }
        
        const data = await response.json()
        setApiData(data)
        setError(null)
      } catch (err) {
        if (err.name === 'AbortError') {
          setError('Request timed out after 30 seconds')
        } else {
          setError(err.message)
        }
      } finally {
        setLoading(false)
      }
    }
    
    fetchData()
    
    // Cleanup function
    return () => {
      controller.abort()
    }
  }, [])

  return (
    <>
      <div>
        <a href="https://vite.dev" target="_blank">
          <img src={viteLogo} className="logo" alt="Vite logo" />
        </a>
        <a href="https://react.dev" target="_blank">
          <img src={reactLogo} className="logo react" alt="React logo" />
        </a>
      </div>
      <h1>🚀 AWS SPA Boilerplate</h1>
      <div className="card">
        <h2>✅ All Stages Complete!</h2>
        <p>
          Congratulations! Your full-stack application is successfully deployed with React SPA, Lambda API, and CloudFront integration.
        </p>
        <button onClick={() => setCount((count) => count + 1)}>
          React is working! Click count: {count}
        </button>
        <div style={{marginTop: '20px', padding: '15px', backgroundColor: '#1e5631', borderRadius: '8px', border: '1px solid #28a745', color: 'white'}}>
          <h3>Full-Stack Integration Complete</h3>
          {loading && <p>Loading...</p>}
          {error && (
            <div>
              <p style={{color: '#ff6b6b'}}>Error: {error}</p>
            </div>
          )}
          {!loading && !error && apiData && (
            <div>
              <p>If you can read the JSON object above, you have successfully completed the entire stack</p>
              <pre style={{
                fontFamily: "'Courier New', Courier, monospace",
                backgroundColor: '#2d4a32',
                padding: '10px',
                borderRadius: '4px',
                textAlign: 'left',
                fontSize: '14px',
                overflow: 'auto'
              }}>
                {JSON.stringify(apiData, null, 2)}
              </pre>
            </div>
          )}
        </div>
      </div>
      <p className="read-the-docs">
        Full-stack React application with API integration served via AWS CloudFront
      </p>
    </>
  )
}

export default App
