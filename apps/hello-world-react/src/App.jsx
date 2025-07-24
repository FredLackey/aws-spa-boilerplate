import { useState } from 'react'
import reactLogo from './assets/react.svg'
import viteLogo from '/vite.svg'
import './App.css'

function App() {
  const [count, setCount] = useState(0)

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
        <h2>✅ Stage D Complete!</h2>
        <p>
          Congratulations! Your React SPA is successfully deployed and served through CloudFront.
        </p>
        <button onClick={() => setCount((count) => count + 1)}>
          React is working! Click count: {count}
        </button>
                 <div style={{marginTop: '20px', padding: '15px', backgroundColor: '#1e5631', borderRadius: '8px', border: '1px solid #28a745', color: 'white'}}>
           <h3>Ready for Stage E</h3>
           <p>You can now proceed to <strong>Stage E: Full-Stack Integration</strong></p>
           <p>The next stage will deploy the Hello World JSON app that connects to your Lambda API.</p>
         </div>
      </div>
      <p className="read-the-docs">
        Static React application successfully served via AWS CloudFront
      </p>
    </>
  )
}

export default App
