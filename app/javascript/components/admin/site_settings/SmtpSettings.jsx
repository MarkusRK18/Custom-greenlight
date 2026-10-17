import React, { useEffect, useState } from 'react';
import {
  Alert, Button, Col, Form, InputGroup, Row, Spinner,
} from 'react-bootstrap';
import { EyeIcon, EyeSlashIcon } from '@heroicons/react/24/outline';
import { useQuery, useQueryClient } from 'react-query';
import axios from '../../../helpers/Axios';

const endpoint = '/admin/smtp_configuration';

export default function SmtpSettings() {
  const queryClient = useQueryClient();
  const query = useQuery('adminSmtp', () => axios.get(`${endpoint}.json`).then((response) => response.data.data), { useErrorBoundary: false });
  const [settings, setSettings] = useState(null);
  const [password, setPassword] = useState('');
  const [visible, setVisible] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState(null);

  useEffect(() => { if (query.data) setSettings(query.data); }, [query.data]);

  if (query.isLoading) return <Spinner animation="border" role="status"><span className="visually-hidden">Loading SMTP settings</span></Spinner>;
  if (query.isError) return <Alert variant="danger">Unable to load SMTP settings. <Button variant="link" onClick={() => query.refetch()}>Retry</Button></Alert>;
  if (!settings) return null;

  const dirty = password !== '' || JSON.stringify(settings) !== JSON.stringify(query.data);
  const change = (name, value) => { setSettings((previous) => ({ ...previous, [name]: value })); setNotice(null); };
  const perform = async (action) => {
    setBusy(true);
    setNotice(null);
    try {
      if (action === 'save') {
        const { data } = await axios.patch(`${endpoint}.json`, { smtp_configuration: { ...settings, password } });
        setPassword('');
        setVisible(false);
        setSettings(data.data);
        queryClient.setQueryData('adminSmtp', data.data);
        queryClient.invalidateQueries('getEnv');
        setNotice({ variant: 'success', text: 'SMTP settings saved. New emails use these settings immediately.' });
      } else {
        const { data } = await axios.post(`${endpoint}/${action}.json`);
        setNotice({ variant: 'success', text: data.data.message });
      }
    } catch (error) {
      const errors = error.response?.data?.errors;
      setNotice({ variant: 'danger', text: Array.isArray(errors) ? errors.join(' ') : errors || 'Unable to complete this action. Try again.' });
    } finally { setBusy(false); }
  };

  const field = (name, label, type = 'text', options = {}) => (
    <Form.Group className="mb-3" controlId={`smtp-${name}`}>
      <Form.Label>{label}</Form.Label>
      <Form.Control type={type} value={settings[name] ?? ''} required={settings.enabled} onChange={(event) => change(name, event.target.value)} {...options} />
    </Form.Group>
  );

  return (
    <Form onSubmit={(event) => { event.preventDefault(); perform('save'); }}>
      <h4>Email / SMTP</h4>
      <p>Connect your mail account to send verification, password reset and invitation emails. Use your mail provider’s SMTP credentials or app password.</p>
      <Alert variant={settings.configured ? 'success' : 'warning'}>
        {settings.configured ? 'Email delivery is configured. Send a test email to confirm delivery.' : 'Email delivery needs setup. Signup and password recovery require working SMTP.'}
      </Alert>
      {notice && <Alert variant={notice.variant} role="status">{notice.text}</Alert>}
      <fieldset disabled={busy}>
        <Form.Check id="smtp-enabled" className="mb-3" label="Enable outgoing email" checked={settings.enabled} onChange={(event) => change('enabled', event.target.checked)} />
        <Row>
          <Col md={8}>{field('host', 'SMTP host', 'text', { placeholder: 'smtp.example.com', autoComplete: 'off' })}</Col>
          <Col md={4}>{field('port', 'Port', 'number', { min: 1, max: 65535 })}</Col>
          <Col md={6}>
            <Form.Group className="mb-3" controlId="smtp-security">
              <Form.Label>Connection security</Form.Label>
              <Form.Select value={settings.security} onChange={(event) => change('security', event.target.value)}>
                <option value="starttls">STARTTLS (usually port 587)</option>
                <option value="tls">TLS (usually port 465)</option>
              </Form.Select>
            </Form.Group>
          </Col>
          <Col md={6}>
            <Form.Group className="mb-3" controlId="smtp-authentication">
              <Form.Label>Authentication</Form.Label>
              <Form.Select value={settings.authentication} onChange={(event) => change('authentication', event.target.value)}>
                <option value="login">Login</option><option value="plain">Plain (over encrypted connection)</option><option value="none">None (trusted relay)</option>
              </Form.Select>
            </Form.Group>
          </Col>
          <Col md={6}>{field('username', 'Username', 'text', { required: settings.enabled && settings.authentication !== 'none', autoComplete: 'off' })}</Col>
          <Col md={6}>
            <Form.Group className="mb-3" controlId="smtp-password">
              <Form.Label>Password / app password</Form.Label>
              <InputGroup>
                <Form.Control type={visible ? 'text' : 'password'} value={password} autoComplete="new-password" aria-describedby="smtp-password-help" onChange={(event) => { setPassword(event.target.value); setNotice(null); }} />
                <Button type="button" variant="outline-secondary" aria-label={visible ? 'Hide SMTP password' : 'Show SMTP password'} aria-pressed={visible} onClick={() => setVisible(!visible)}>
                  {visible ? <EyeSlashIcon width={20} aria-hidden="true" /> : <EyeIcon width={20} aria-hidden="true" />}
                </Button>
              </InputGroup>
              <Form.Text id="smtp-password-help">{settings.password_configured ? 'A password is saved. Leave blank to keep it.' : 'No password saved.'}</Form.Text>
            </Form.Group>
          </Col>
          <Col md={6}>{field('sender_email', 'Sender email', 'email')}</Col>
          <Col md={6}>{field('sender_name', 'Sender name', 'text', { required: false })}</Col>
          <Col md={12}>{field('domain', 'HELO domain', 'text', { placeholder: 'Your mail domain, for example siet.ac.in' })}</Col>
        </Row>
        <Button type="submit" variant="brand" className="me-2 mb-2">{busy && <Spinner size="sm" animation="border" className="me-2" />}Save settings</Button>
        <Button type="button" variant="outline-secondary" className="me-2 mb-2" disabled={dirty || !settings.configured} onClick={() => perform('test_connection')}>Test connection</Button>
        <Button type="button" variant="outline-secondary" className="mb-2" disabled={dirty || !settings.configured} onClick={() => perform('test_email')}>Send test email to me</Button>
        <p className="text-muted small">{dirty ? 'Save changes before testing. ' : ''}Test emails go to your signed-in account. SMTP acceptance does not guarantee inbox delivery.</p>
      </fieldset>
    </Form>
  );
}
