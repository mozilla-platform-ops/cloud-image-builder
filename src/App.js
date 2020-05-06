import React from 'react'
import Commits from './Commits';
import Container from 'react-bootstrap/Container';

class App extends React.Component {
  state = {
    commits: []
  };
  /*
  note: to run locally, a cors proxy is required.

  to install a local cors proxy:
  $ sudo npm install -g local-cors-proxy

  to run a local cors proxy with authenticated github requests:
  $ lcp --proxyUrl https://grenade:$(pass github/grenade/token/travisci-minionsmanaged-observations)@api.github.com
  */
  apiBase = (window.location.hostname === 'localhost')
    ? 'http://localhost:8010/proxy'
    : 'https://api.github.com';

  componentDidMount() {
    fetch(
      this.apiBase + '/repos/mozilla-platform-ops/cloud-image-builder/commits'
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
          }))
        }));
      }
    })
    .catch(console.log);
  }

  render() {
    return (
      <Container>
        <Commits commits={this.state.commits} />
      </Container>
    );
  }
}

export default App;
