import { useState, useEffect, FormEvent } from 'react'
import './App.css'

interface HelloResponse {
  message: string
  timestamp: string
  environment: string
}

interface Item {
  Id: number
  Name: string
  CreatedAt: string
}

export default function App() {
  const [hello, setHello] = useState<HelloResponse | null>(null)
  const [items, setItems] = useState<Item[]>([])
  const [newItemName, setNewItemName] = useState('')
  const [apiLoading, setApiLoading] = useState(true)
  const [apiError, setApiError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => {
    fetchHello()
    fetchItems()
  }, [])

  async function fetchHello() {
    try {
      const res = await fetch('/api/hello')
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      setHello(await res.json())
    } catch {
      setApiError('Could not reach the API. Is the Functions emulator running?')
    } finally {
      setApiLoading(false)
    }
  }

  async function fetchItems() {
    try {
      const res = await fetch('/api/items')
      if (!res.ok) return
      const data = await res.json()
      setItems(data.items ?? [])
    } catch {
      // Non-critical — items section shows empty state
    }
  }

  async function handleCreateItem(e: FormEvent) {
    e.preventDefault()
    if (!newItemName.trim()) return
    setSubmitting(true)
    try {
      const res = await fetch('/api/items', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: newItemName.trim() }),
      })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      setItems(prev => [data.item, ...prev])
      setNewItemName('')
    } catch {
      setApiError('Failed to create item.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="container">
      <header className="header">
        <h1>My App</h1>
        <p className="subtitle">Hello World — Azure Static Web App · Functions · SQL</p>
      </header>

      <section className="card">
        <h2>API Status</h2>
        {apiLoading ? (
          <p className="muted">Connecting to API...</p>
        ) : apiError ? (
          <p className="error">{apiError}</p>
        ) : hello ? (
          <div className="api-info">
            <p className="success">{hello.message}</p>
            <p className="muted">Environment: {hello.environment}</p>
            <p className="muted">Server time: {new Date(hello.timestamp).toLocaleString()}</p>
          </div>
        ) : null}
      </section>

      <section className="card">
        <h2>Items (SQL Database)</h2>
        <form onSubmit={handleCreateItem} className="form">
          <input
            type="text"
            value={newItemName}
            onChange={e => setNewItemName(e.target.value)}
            placeholder="New item name..."
            className="input"
            disabled={submitting}
            maxLength={255}
          />
          <button
            type="submit"
            className="button"
            disabled={submitting || !newItemName.trim()}
          >
            {submitting ? 'Saving...' : 'Add'}
          </button>
        </form>

        {items.length === 0 ? (
          <p className="muted">No items yet. Add one above.</p>
        ) : (
          <ul className="item-list">
            {items.map(item => (
              <li key={item.Id} className="item">
                <span className="item-name">{item.Name}</span>
                <span className="item-date">
                  {new Date(item.CreatedAt).toLocaleDateString()}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  )
}
