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
  $ lcp --proxyUrl https://grenade:$(pass github/grenade/token/cloud-image-builder)@api.github.com
  */

  componentDidMount() {
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
      <Container>
        <Commits commits={this.state.commits} latest={this.state.latest} />
      </Container>
    );
  }
}

export default App;
