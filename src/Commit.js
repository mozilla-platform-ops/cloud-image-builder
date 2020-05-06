import React from 'react'
import Card from 'react-bootstrap/Card';
import Row from 'react-bootstrap/Row';
import Image from 'react-bootstrap/Image';
import Statuses from './Statuses';

class Commit extends React.Component {
  state = {
    contexts: [],
    statuses: []
  };
  /*
  note: to run locally, a cors proxy is required.

  to install a local cors proxy:
  $ sudo npm install -g local-cors-proxy

  to run a local cors proxy with authenticated github requests:
  $ lcp --proxyUrl https://grenade:$(pass github/grenade/token/cloud-image-builder)@api.github.com
  */

  componentDidMount() {
    fetch(
      (window.location.hostname === 'localhost')
        ? 'http://localhost:8010/proxy/repos/mozilla-platform-ops/cloud-image-builder/commits'
        : 'https://grenade-cors-proxy.herokuapp.com/https://api.github.com/repos/mozilla-platform-ops/cloud-image-builder/commits/' + this.props.commit.sha + '/statuses'
    )
    .then(responseGithubApiStatuses => responseGithubApiStatuses.json())
    .then((githubCommitStatuses) => {
      if (githubCommitStatuses.length) {
        this.setState(state => ({
          contexts: [...new Set(githubCommitStatuses.map(s => s.context))].sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase())),
          statuses: githubCommitStatuses.filter(s => s.state !== 'pending')
        }));
      }
    })
    .catch(console.log);
  }

  render() {
    return (
      <li style={{ marginTop: '10px' }}>
        <Row>
          <Card style={{ width: '100%' }}>
            <Card.Header>
              <a href={this.props.commit.url}>
                { this.props.commit.sha.substring(0, 7) }
              </a>
              &nbsp;
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
            <Card.Body>
              <pre>
                { this.props.commit.message.join('\n') }
              </pre>
              <Statuses contexts={this.state.contexts} statuses={this.state.statuses} />
            </Card.Body>
          </Card>
        </Row>
      </li>
    );
  }
}

export default Commit;
