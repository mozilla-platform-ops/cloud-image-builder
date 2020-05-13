import React from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faCloud, faImage, faHammer } from '@fortawesome/free-solid-svg-icons'
import Commits from './Commits';
import Badge from  'react-bootstrap/Badge';
import Button from 'react-bootstrap/Button';
import Col from 'react-bootstrap/Col';
import Container from 'react-bootstrap/Container';
import Form from 'react-bootstrap/Form';
import Row from 'react-bootstrap/Row';
import Cookies from 'universal-cookie';
import StatusBadgeVariantMap from './StatusBadgeVariantMap';

class App extends React.Component {

  interval;

  cookies = new Cookies();
  state = {
    commits: [],
    settings: {
      fluid: this.cookies.get('fluid'),
      showAllTasks: this.cookies.get('showAllTasks')
    }
  };
  /*
  note: to run locally, a cors proxy is required.

  to install a local cors proxy:
  $ sudo npm install -g local-cors-proxy

  to run a local cors proxy with authenticated github requests:
  $ lcp --proxyUrl https://grenade:$(pass github/grenade/token/cloud-image-builder)@api.github.com
  */

  componentDidMount() {
    if (this.cookies.get('fluid') === null) {
      this.cookies.set('fluid', true, { path: '/' });
    }
    this.getCommits();

    // refresh commit list every 5 minutes
    // https://blog.stvmlbrn.com/2019/02/20/automatically-refreshing-data-in-react.html
    let intervalMs = (5 * 60 * 1000);
    this.interval = setInterval(this.getCommits.bind(this), intervalMs);
  }

  componentWillUnmount() {
    clearInterval(this.interval);
  }

  getCommits() {
    fetch(
      (window.location.hostname === 'localhost')
        ? 'http://localhost:8010/proxy/repos/mozilla-platform-ops/cloud-image-builder/commits'
        : 'https://grenade-cors-proxy.herokuapp.com/https://api.github.com/repos/mozilla-platform-ops/cloud-image-builder/commits'
    )
    .then(responseGithubApiCommits => responseGithubApiCommits.json())
    .then((githubCommits) => {
      if (githubCommits.length) {
        this.setState(state => ({
          commits: githubCommits.map(c => ({
            sha: c.sha,
            url: c.html_url,
            author: {...c.commit.author, ...{ id: c.author.id, username: c.author.login, avatar: c.author.avatar_url }},
            committer: {...c.commit.committer, ...{ id: c.committer.id, username: c.committer.login, avatar: c.committer.avatar_url }},
            message: c.commit.message.split('\n').filter(line => line !== ''),
            verification: c.commit.verification
          })),
          latest: githubCommits[0].sha
        }));
      } else {
        console.log(githubCommits)
      }
    })
    .catch(console.log);
  }

  render() {
    return (
      <Container fluid={this.state.settings.fluid}>
        <Row>
          <h1 style={{ padding: '0 1em' }}>
            <FontAwesomeIcon style={{ marginRight: '0.4em' }} icon={faCloud} />
            <FontAwesomeIcon style={{ marginRight: '0.4em' }} icon={faImage} />
            <FontAwesomeIcon style={{ marginRight: '0.4em' }} icon={faHammer} />
            recent commits and builds
          </h1>
        </Row>
        <Row>
          <Col>
            <Commits commits={this.state.commits} latest={this.state.latest} settings={this.state.settings} />
          </Col>
          <Col sm="2">
            <strong>
              legend
            </strong>
            <br style={{ marginTop: '20px' }} />
            task status:
            {
              Object.keys(StatusBadgeVariantMap).map(status => (
                <Badge
                  style={{ display: 'block', margin: '10px 20px' }}
                  variant={StatusBadgeVariantMap[status]}>
                  {status}
                </Badge>
              ))
            }
            image deployment:
            <br />
            <Button
              style={{ marginLeft: '0.3em' }}
              variant="outline-info"
              size="sm">
              worker pool <Badge variant="info">region count</Badge>
            </Button>
            <hr />
            <strong>
              display settings:
            </strong>
            <br />
            <Form.Check 
              type="switch"
              id="showAllTasks"
              label="show all tasks"
              checked={this.state.settings.showAllTasks}
              onChange={
                () => {
                  this.cookies.set('showAllTasks', (!this.state.settings.showAllTasks), { path: '/' });
                  this.setState(state => ({settings: { showAllTasks: !state.settings.showAllTasks, fluid: state.settings.fluid }}));
                }
              }
            />
            <br />
            <Form.Check 
              type="switch"
              id="fluid"
              label="fluid"
              checked={this.state.settings.fluid}
              onChange={
                () => {
                  this.cookies.set('fluid', (!this.state.settings.fluid), { path: '/' });
                  this.setState(state => ({settings: { fluid: !state.settings.fluid, showAllTasks: state.settings.showAllTasks }}));
                }
              }
            />
          </Col>
        </Row>
      </Container>
    );
  }
}

export default App;
