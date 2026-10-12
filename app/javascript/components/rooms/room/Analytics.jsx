import React, { useState } from 'react';
import { Alert, Button, Card, Col, Row, Table, Modal, ProgressBar } from 'react-bootstrap';
import { useParams } from 'react-router-dom';
import { useQuery } from 'react-query';
import axios from '../../../helpers/Axios';
import { UsersIcon, ChartPieIcon, ClipboardDocumentListIcon, CheckIcon } from '@heroicons/react/24/outline';

const time = (seconds) => {
  const total = Math.floor(Math.max(0, Number(seconds) || 0));
  return [Math.floor(total / 3600), Math.floor((total % 3600) / 60), total % 60].map((part) => String(part).padStart(2, '0')).join(':');
};

export default function Analytics() {
  const { friendlyId } = useParams();
  const [sessionId, setSessionId] = useState(null);
  const { data: sessions, isLoading, isError } = useQuery(
    ['roomAnalytics', friendlyId],
    () => axios.get(`/rooms/${friendlyId}/analytics.json`).then((response) => response.data.data),
    { refetchInterval: 15000 },
  );
  if (sessionId) return <SessionDashboard friendlyId={friendlyId} sessionId={sessionId} onBack={() => setSessionId(null)} />;
  if (isLoading) return <div className="wide pt-4">Loading sessions…</div>;
  if (isError) return <Alert variant="danger">Unable to load meeting analytics.</Alert>;
  return (
    <div className="wide py-4">
      <h3 className="text-brand">Session history</h3>
      {!sessions?.length ? <Alert variant="info">Saved sessions will appear after meetings end and SIETConnect finishes processing their analytics.</Alert> : (
        <Table responsive striped hover>
          <thead><tr><th>Date and time</th><th>Start time</th><th>End time</th><th>Duration</th><th>No. of participants</th></tr></thead>
          <tbody>{sessions.map((session) => (
            <tr key={session.id}>
              <td><Button variant="link" className="text-brand p-0" onClick={() => setSessionId(session.id)}>{new Date(session.started_at || session.saved_at).toLocaleString()}</Button></td>
              <td>{session.started_at ? new Date(session.started_at).toLocaleTimeString() : 'Unavailable'}</td>
              <td>{session.ended_at ? new Date(session.ended_at).toLocaleTimeString() : 'Unavailable'}</td>
              <td>{time(session.duration_seconds)}</td><td>{session.participant_count}</td>
            </tr>
          ))}</tbody>
        </Table>
      )}
    </div>
  );
}

function SessionDashboard({ friendlyId, sessionId, onBack }) {
  const [sortAscending, setSortAscending] = useState(true);
  const [showHelp, setShowHelp] = useState(false);
  const { data, isLoading, isError } = useQuery(
    ['roomAnalyticsSession', friendlyId, sessionId],
    () => axios.get(`/rooms/${friendlyId}/analytics/${sessionId}.json`).then((response) => response.data.data),
  );
  if (isLoading) return <div className="wide pt-4">Loading dashboard…</div>;
  if (isError || !data) return <div className="wide pt-4"><Button variant="brand-outline" onClick={onBack}>Back to sessions</Button><Alert variant="danger">Unable to load this session.</Alert></div>;
  const attendees = [...(data.attendees || [])].sort((a, b) => (sortAscending ? 1 : -1) * (a.name || '').localeCompare(b.name || ''));
  const metric = (source, keys) => {
    const value = keys.map((key) => source?.[key]).find((item) => item !== undefined && item !== null);
    if (value === undefined) return 'N/A';
    if (Array.isArray(value)) return value.length;
    return Number.isFinite(Number(value)) ? Number(value) : 'N/A';
  };
  const duration = (value) => (value === undefined || value === null ? 'N/A' : time(value));
  const date = (value) => (value ? new Date(value).toLocaleString() : 'N/A');
  const engagement = (user, keys) => metric(user.engagement, keys);
  const cards = [
    { label: 'Total Number Of Users', value: attendees.length, icon: UsersIcon, color: 'pink' },
    { label: 'Activity Score', value: metric(data, ['activity_score', 'activityScore']), icon: ChartPieIcon, color: 'green' },
    { label: 'Timeline', value: metric(data, ['timeline']), color: 'gray' },
    { label: 'Polls', value: metric(data, ['polls']), icon: ClipboardDocumentListIcon, color: 'blue' },
    { label: 'Quizzes', value: metric(data, ['quizzes']), icon: CheckIcon, color: 'orange' },
  ];
  const download = () => {
    const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = 'meeting-analytics.json';
    link.click();
    URL.revokeObjectURL(url);
  };
  return (
    <div className="analytics-dashboard py-4">
      <Button variant="brand-outline" className="mb-3" onClick={onBack}>Back to sessions</Button>
      <div className="d-flex justify-content-between flex-wrap gap-3 mb-3">
        <div><h3>Learning Analytics Dashboard</h3><strong>{data.meeting_name}</strong></div>
        <div className="text-end text-muted">
          <div>{data.start ? new Date(data.start).toLocaleDateString() : 'N/A'} <span className="analytics-status offline">Ended</span></div>
          <div>Duration: {duration(data.duration)}</div>
        </div>
      </div>
      {data.meeting_description && <p className="meeting-description text-muted">{data.meeting_description}</p>}
      <Row className="g-3 mb-4">
        {cards.map(({ label, value, icon: Icon, color }) => (
          <Col xs={12} sm={6} xl={3} key={label}>
            <Card body className={`analytics-stat ${color}`}>
              <div><h5>{value}</h5><span>{label}</span></div>
              {Icon && <span className={`analytics-stat-icon ${color}`}><Icon className="hi-m" /></span>}
            </Card>
          </Col>
        ))}
      </Row>
      <h4>Overview</h4>
      <Table responsive className="analytics-overview align-middle">
        <thead><tr>
          <th><Button variant="link" className="p-0 text-muted" onClick={() => setSortAscending(!sortAscending)}>User {sortAscending ? '↑' : '↓'}</Button></th>
          <th>Online time</th><th>Talk time</th><th>Webcam time</th><th>Messages</th><th>Reactions</th><th>Raise hands</th>
          <th>Whiteboard annotations</th><th>Shared notes</th><th>Activity score</th><th>Status</th>
        </tr></thead>
        <tbody>{attendees.map((user, index) => (
          <tr key={`${user.ext_user_id || 'participant'}-${index}`}>
            <td><div className="d-flex align-items-center gap-2">
              <span className="analytics-avatar">{(user.name || '?').slice(0, 2)}</span>
              <div><strong className="text-decoration-underline">{user.name}</strong>
                {(user.joins || []).map((joined, i) => <small className="d-block text-muted" key={`join-${i}`}>↪ {date(joined)}</small>)}
                {(user.leaves || []).map((left, i) => <small className="d-block text-muted" key={`leave-${i}`}>↩ {date(left)}</small>)}
              </div>
            </div></td>
            <td>{duration(user.duration)}<ProgressBar className="analytics-online-bar" variant="success" now={data.duration > 0 ? Math.min(100, ((user.duration || 0) / data.duration) * 100) : 0} /></td>
            <td>{duration(user.engagement?.talk_time)}</td>
            <td>{duration(user.engagement?.webcam_time ?? user.webcam_time)}</td>
            <td>{engagement(user, ['chats'])}</td><td>{engagement(user, ['emojis'])}</td><td>{engagement(user, ['raisehand'])}</td>
            <td>{engagement(user, ['whiteboard_annotations', 'annotations'])}</td>
            <td>{engagement(user, ['shared_notes', 'notes'])}</td>
            <td>{metric(user, ['activity_score', 'activityScore'])}</td>
            <td><span className="analytics-status offline">Offline</span></td>
          </tr>
        ))}</tbody>
      </Table>
      <div className="analytics-footer d-flex justify-content-between align-items-center flex-wrap gap-3 mt-4 pt-4">
        <small className="text-muted">Last updated at {date(data.saved_at)}</small>
        <div className="d-flex gap-2">
          <Button variant="brand-outline" onClick={download}>↓ Download Session Data</Button>
          <Button variant="brand-outline" onClick={() => setShowHelp(true)}>Help</Button>
        </div>
      </div>
      <Modal show={showHelp} onHide={() => setShowHelp(false)} centered>
        <Modal.Header closeButton><Modal.Title>Analytics help</Modal.Title></Modal.Header>
        <Modal.Body>
          <p>This dashboard shows the saved data for this completed session. Online time is the participant’s total connection time; the bar shows their share of the meeting duration.</p>
          <p>Messages, reactions and raised hands are recorded event counts. N/A means SIETConnect did not include that metric in the saved data. Zero means the recorded count was zero.</p>
          <p>Use Download Session Data to export the saved JSON, or Back to sessions to open another meeting session.</p>
        </Modal.Body>
      </Modal>
    </div>
  );
}
