import React from 'react'

import Card from 'react-bootstrap/Card';
import Accordion from 'react-bootstrap/Accordion';
import Badge from 'react-bootstrap/Badge';
import Button from 'react-bootstrap/Button';
import Image from 'react-bootstrap/Image';
import Spinner from 'react-bootstrap/Spinner';

import CommitMessage from './CommitMessage';
import Statuses from './Statuses';
import StatusBadgeVariantMap from './StatusBadgeVariantMap';
//import { useInterval } from './useInterval';
import { CaretDown, CaretRight } from 'react-bootstrap-icons';

const minIntervalMs = 5000; // minimum random refresh interval in milliseconds
const maxIntervalMs = 60000; // maximum random refresh interval in milliseconds

class Commit extends React.Component {

  interval;

  state = {
    summary: {
      task: {
        completed: {},
        failed: {},
        exception: {},
        running: {},
        pending: {},
        unscheduled: {}
      },
      image: {}
    },
    contexts: [],
    statuses: [],
    expanded: false
  };

  constructor(props) {
    super(props);
    this.appendToSummary = this.appendToSummary.bind(this);
  }

  appendToSummary(summary) {
    this.setState(state => ({
      summary: {
        task: {
          completed: { ...state.summary.task.completed, ...summary.task.completed },
          failed: { ...state.summary.task.failed, ...summary.task.failed },
          exception: { ...state.summary.task.exception, ...summary.task.exception },
          running: { ...state.summary.task.running, ...summary.task.running },
          pending: { ...state.summary.task.pending, ...summary.task.pending },
          unscheduled: { ...state.summary.task.unscheduled, ...summary.task.unscheduled }
        },
        image: { ...state.summary.image, ...summary.image }
      }
    }));
  }

  /*
  note: to run locally, a cors proxy is required.

  to install a local cors proxy:
  $ sudo npm install -g local-cors-proxy

  to run a local cors proxy with authenticated github requests:
  $ lcp --proxyUrl https://grenade:$(pass github/grenade/token/cloud-image-builder)@api.github.com
  */

  componentDidMount() {
    this.setState(state => ({ expanded: this.props.expand }));
    

    // refresh data in this component at a random interval, in
    // order to prevent all components updating simultaneously
    // https://blog.stvmlbrn.com/2019/02/20/automatically-refreshing-data-in-react.html
    let interval = Math.floor(Math.random() * (maxIntervalMs - minIntervalMs)) + minIntervalMs;
    this.interval = setInterval(this.getBuildStatuses.bind(this), interval);
    /*
    useInterval(async () => {
      this.getBuildStatuses();
    }, interval);
    */
  }

  componentWillUnmount() {
    clearInterval(this.interval);
  }

  getBuildStatuses() {
    fetch(
      (window.location.hostname === 'localhost')
        ? 'http://localhost:8010/proxy/repos/mozilla-platform-ops/cloud-image-builder/commits/' + this.props.commit.sha + '/statuses'
        : 'https://grenade-cors-proxy.herokuapp.com/https://api.github.com/repos/mozilla-platform-ops/cloud-image-builder/commits/' + this.props.commit.sha + '/statuses'
    )
    .then(responseGithubApiStatuses => responseGithubApiStatuses.json())
    .then((githubCommitStatuses) => {
      if (githubCommitStatuses.length) {
        this.setState(state => ({
          contexts: [...new Set(githubCommitStatuses.map(s => s.context))].sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase())),
          statuses: githubCommitStatuses//.filter(s => s.state !== 'pending')
        }));
      }
    })
    .catch(console.log);
  }

  render() {
    return (
      <Card style={{ width: '100%', marginTop: '10px' }}>
        <Card.Header>
          <Accordion.Toggle as={Button} variant="link" eventKey={this.props.commit.sha} onClick={() => {
            this.setState(state => ({expanded: !state.expanded}))
          }}>
            {(this.state.expanded) ? <CaretDown /> : <CaretRight />}
          </Accordion.Toggle>
          {
            new Intl.DateTimeFormat('en-GB', {
              year: 'numeric',
              month: 'short',
              day: '2-digit',
              hour: 'numeric',
              minute: 'numeric',
              timeZoneName: 'short'
            }).format(new Date(this.props.commit.committer.date))
          }
          &nbsp;
          <a href={this.props.commit.url}>
            { this.props.commit.sha.substring(0, 7) }
          </a>
          {
            (Object.keys(this.state.summary.task).some(k => (Object.keys(this.state.summary.task[k]).length > 0)))
              ? (
                  Object.keys(this.state.summary.task).filter(k => Object.keys(this.state.summary.task[k]).length > 0).map(k => (
                    <Badge
                      key={k}
                      style={{ marginLeft: '0.3em' }}
                      variant={StatusBadgeVariantMap[k]}>
                      {Object.keys(this.state.summary.task[k]).length}
                    </Badge>
                  ))
                )
              : (
                  <Spinner
                    style={{ marginLeft: '0.3em' }}
                    animation="border"
                    size="sm"
                    variant="info" />
                )
          }
          <Image
            src={this.props.commit.author.avatar}
            alt={this.props.commit.author.name}
            title={this.props.commit.author.name}
            rounded={true}
            style={{ width: '30px', height: '30px', marginLeft: '10px' }}
            className="float-right" />
          <span className="float-right">
            { this.props.commit.author.username }
          </span>
        </Card.Header>
        {
          (Object.keys(this.state.summary.image).length)
          ? (
              <Card.Body>
                {
                  Object.keys(this.state.summary.image).sort().map(pool => (
                    <Button
                      key={pool}
                      style={{ marginLeft: '0.3em' }}
                      variant="outline-info"
                      size="sm">
                      {pool} <Badge variant="info">{this.state.summary.image[pool]}</Badge>
                    </Button>
                  ))
                }
              </Card.Body>
            )
          : ''
        }
        <Accordion.Collapse eventKey={this.props.commit.sha}>
          <Card.Body>
            <CommitMessage message={this.props.commit.message} />
            <Statuses contexts={this.state.contexts} statuses={this.state.statuses} appender={this.appendToSummary} settings={this.props.settings} />
          </Card.Body>
        </Accordion.Collapse>
      </Card>
    );
  }
}

export default Commit;
