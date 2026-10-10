import React from 'react';
import { Alert, Button, Card, Col, Row, Table } from 'react-bootstrap';
import { useParams } from 'react-router-dom';
import { useQuery } from 'react-query';
import axios from '../../../helpers/Axios';

const time = (seconds) => {
  const total = Math.floor(Math.max(0, Number(seconds) || 0));
  return [Math.floor(total / 3600), Math.floor((total % 3600) / 60), total % 60].map((part) => String(part).padStart(2, '0')).join(':');
};

export default function Analytics() {
  const { friendlyId } = useParams();
  const { data, isLoading, isError } = useQuery(
    ['roomAnalytics', friendlyId],
    () => axios.get(`/rooms/${friendlyId}/analytics.json`).then((response) => response.data.data),
    { refetchInterval: 15000 },
  );
  if (isLoading) return <div className="wide pt-4">Loading analytics…</div>;
  if (isError) return <Alert variant="danger">Unable to load meeting analytics.</Alert>;
  if (!data) return <div className="wide pt-4"><Alert variant="info">Analytics will appear after a new meeting ends and BigBlueButton finishes processing its session data.</Alert></div>;
  const attendees = data.attendees || [];
  const count = (value) => (Array.isArray(value) ? value.length : Number(value) || 0);
  const download = () => {
    const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = 'meeting-analytics.json';
    link.click();
    URL.revokeObjectURL(url);
  };
  return (
    <div className="wide py-4">
      <h3 className="text-brand">Learning Analytics Dashboard</h3>
      <p>Duration: {time(data.duration)} {data.finish && <span className="badge bg-secondary ms-2">Ended</span>}</p>
      <p className="text-muted">{data.start && `Started: ${new Date(data.start).toLocaleString()}`} {data.finish && ` · Ended: ${new Date(data.finish).toLocaleString()}`}</p>
      <Row className="g-3 mb-4">
        {[
          ['Total Number Of Users', attendees.length],
          ['Messages', attendees.reduce((sum, user) => sum + count(user.engagement?.chats), 0)],
          ['Polls', count(data.polls)],
          ['Quizzes', count(data.quizzes)],
        ].map(([label, value]) => <Col md={6} key={label}><Card body><h4 className="text-brand">{value}</h4>{label}</Card></Col>)}
      </Row>
      <h4>Overview</h4>
      <Table responsive striped>
        <thead><tr><th>User</th><th>Online time</th><th>Talk time</th><th>Messages</th><th>Reactions</th><th>Raise hands</th></tr></thead>
        <tbody>{attendees.map((user, index) => (
          <tr key={user.ext_user_id || index}>
            <td>{user.name}</td><td>{time(user.duration)}</td><td>{time(user.engagement?.talk_time)}</td>
            <td>{count(user.engagement?.chats)}</td><td>{count(user.engagement?.emojis)}</td><td>{count(user.engagement?.raisehand)}</td>
          </tr>
        ))}</tbody>
      </Table>
      <Button variant="brand-outline" onClick={download}>Download Session Data</Button>
    </div>
  );
}
