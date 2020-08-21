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
import Slider from 'rc-slider';

class App extends React.Component {

  interval;

  cookies = new Cookies();
  state = {
    commits: [],
    settings: {
      fluid: (this.cookies.get('fluid') === undefined || this.cookies.get('fluid') === null) ? true : (this.cookies.get('fluid') === 'true'),
      limit: (this.cookies.get('limit') === undefined || this.cookies.get('limit') === null) ? { commits: 1, tasks: ['03', '04'] } : this.cookies.get('limit')
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
    if (this.cookies.get('fluid') === undefined || this.cookies.get('fluid') === null) {
      this.cookies.set('fluid', true, { path: '/', sameSite: 'strict' });
    }
    if (this.cookies.get('limit') === undefined || this.cookies.get('limit') === null) {
      this.cookies.set(
        'limit',
        this.state.settings.limit,
        {
          path: '/',
          sameSite: 'strict'
        });
    }
    this.getCommits(this.state.settings.limit.commits);

    // refresh commit list every 5 minutes
    // https://blog.stvmlbrn.com/2019/02/20/automatically-refreshing-data-in-react.html
    let intervalMs = (5 * 60 * 1000);
    this.interval = setInterval(this.getCommits.bind(this), intervalMs);
  }

  componentWillUnmount() {
    clearInterval(this.interval);
  }

  getCommits(limit) {
    if (limit === null || limit === undefined) {
      limit = (this.cookies.get('limit') === undefined || this.cookies.get('limit') === null) ? 1 : this.cookies.get('limit').commits;
    }
    fetch(
      (window.location.hostname === 'localhost')
        ? 'http://localhost:8010/proxy/repos/mozilla-platform-ops/cloud-image-builder/commits'
        : 'https://grenade-cors-proxy.herokuapp.com/https://api.github.com/repos/mozilla-platform-ops/cloud-image-builder/commits'
    )
    .then(responseGithubApiCommits => responseGithubApiCommits.json())
    .then((githubCommits) => {
      if (githubCommits.length) {
        this.setState(state => ({
          commits: githubCommits.slice(0, limit).map(c => ({
            sha: c.sha,
            url: c.html_url,
            author: {...c.commit.author, ...{ id: c.author.id, username: c.author.login, avatar: c.author.avatar_url }},
            committer: {...c.commit.committer, ...{ id: c.committer.id, username: c.committer.login, avatar: c.committer.avatar_url }},
            message: c.commit.message.split('\n').filter(line => line !== ''),
            verification: c.commit.verification
          })),
          latest: githubCommits[0].sha
        }));
      }
    })
    .catch(console.log);
  }

  render() {
    return (
      <Container fluid={(this.state.settings.fluid === undefined || this.state.settings.fluid === null) ? true : this.state.settings.fluid}>
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
                  key={status}
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
            <br  />
            <Slider
              defaultValue={ this.state.settings.limit.commits }
              min={1}
              max={30}
              onChange={
                (commitLimit) => {
                  let limit = { commits: commitLimit, tasks: this.state.settings.limit.tasks };
                  this.cookies.set('limit', limit, { path: '/', sameSite: 'strict' });
                  this.setState(state => ({ settings: { fluid: state.settings.fluid, limit: limit }}));
                  this.getCommits(commitLimit);
                }
              }
              style={{ marginTop: '20px' }} />
            limit commits ({this.state.settings.limit.commits})
            <br style={{ marginBottom: '20px' }} />
            <Form.Check 
              type="switch"
              id="showAllTasks"
              label="all tasks"
              checked={(this.state.settings.limit.tasks.length > 2)}
              onChange={
                () => {
                  let limit = { commits: this.state.settings.limit.commits, tasks: (!(this.state.settings.limit.tasks.length > 2)) ? ['00', '01', '02', '03', '04'] : ['03', '04'] };
                  this.cookies.set('limit', limit, { path: '/', sameSite: 'strict' });
                  this.setState(state => ({ settings: { fluid: state.settings.fluid, limit: limit }}));
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
                  let fluid = !this.state.settings.fluid;
                  this.cookies.set('fluid', fluid, { path: '/', sameSite: 'strict' });
                  this.setState(state => ({ settings: { fluid: fluid, limit: state.settings.limit }}));
                }
              }
            />
            <hr />
            <p className="text-muted">
              <strong>cloud image builder</strong> automates the creation of windows machine images on cloud platforms. it accomplishes this using tasks
              running in mozilla's taskcluster ci framework, on workers and resources that run within the target cloud platforms. the objective is
              carried out by the following task sequence implementation:
            </p>
            <ol type="1" start="0" className="text-muted">
              <li>
                <strong>setup tasks</strong>
                <ul>
                  <li>decision task: analyse commit message and generate tasks</li>
                  <li>cleanup tasks: purge deprecated and orphaned resources on the target cloud platforms</li>
                  <li>validation tasks: lint and validate the cib repository commit</li>
                </ul>
              </li>
              <li>
                <strong>disk image builds</strong>
                <ol type="i">
                  <li>download and mount a windows iso</li>
                  <li>create and mount a virtual hard disk (vhd)</li>
                  <li>install windows setup files from the iso to the vhd</li>
                  <li>add target platform specific drivers and installer packages to the vhd in conventional locations to be installed by the windows setup process (sysprep) later</li>
                  <li>add a sysprep unattend.xml instruction set to the vhd</li>
                  <li>dismount and save the prepared vhd</li>
                  <li>upload vhd to the target cloud platform</li>
                </ol>
              </li>
              <li>
                <strong>machine image builds</strong>
                <ol type="i">
                  <li>mount disk image (vhd) as a virtual machine (vm) instance boot disk on the target cloud platform and boot the vm</li>
                  <li>allow time for the vm to boot, and for it to discover and execute the instruction set from its included sysprep configuration and unattend file</li>
                  <li>simulate manual restarts (by issuing cloud api restart requests) as required by the sysprep instruction set</li>
                  <li>trigger the execution of any additional configured execution instructions or bootstrapping scripts</li>
                  <li>await final shutdown of the vm</li>
                  <li>capture vm as a platform specific machine image</li>
                  <li>tag machine image with metadata and mark as generalized or specialized as per image sysprep configuration</li>
                </ol>
              </li>
              <li>
                <strong>generate taskcluster worker-pool configurations</strong>
                <ol type="i">
                  <li>generate markdown describing new machine images</li>
                  <li>generate yaml defining new machine images</li>
                  <li>update taskcluster worker-manager with new pool definitions</li>
                </ol>
              </li>
              <li>
                <strong>validate new machine images (not implemented)</strong>
                <ol type="i">
                  <li>run tasks against new worker pools that verify the pool capacity to claim and complete tasks</li>
                  <li>run tasks against new worker pools that verify the pool competence to produce expected output and artifacts</li>
                </ol>
              </li>
            </ol>
            <p className="text-muted">
              this page is a simple react app which monitors <a href="https://github.com/mozilla-platform-ops/cloud-image-builder/commits/master">commits</a> to the master branch of the <a href="https://github.com/mozilla-platform-ops/cloud-image-builder">mozilla-platform-ops/cloud-image-builder</a> repository and the resulting <a href="https://travis-ci.org/github/mozilla-platform-ops/cloud-image-builder/builds">travis-ci builds</a> and taskcluster tasks (<a href="https://stage.taskcluster.nonprod.cloudops.mozgcp.net/tasks/index/project.relops.cloud-image-builder">staging</a>, <a href="https://firefox-ci-tc.services.mozilla.com/tasks/index/project.relops.cloud-image-builder">production</a>) which produce cloud machine images of the various windows operating system editions and configurations used by firefox ci to build and test gecko products on the windows platform.
            </p>
            <p className="text-muted">
              the source code for this page is hosted in the <a href="https://github.com/mozilla-platform-ops/cloud-image-builder/tree/react">react branch</a> of the same repository.
            </p>
          </Col>
        </Row>
      </Container>
    );
  }
}

export default App;
