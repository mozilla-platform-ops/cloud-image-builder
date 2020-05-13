import React from 'react'


class Image extends React.Component {
  re = /^((north|south|east|west|(north-|south-|west-)?central)-us(-2)?)-(.*)-(win.*)-([a-f0-9]{7})-([a-f0-9]{7})$/i;
  state = {
    domain: null,
    pool: null,
    region: null,
    sha: {
      bootstrap: null,
      disk: null
    }
  }

  componentDidMount() {
    let name = this.props.image.substring(this.props.image.lastIndexOf('/') + 1);
    let matches = name.match(this.re);
    this.setState(state => ({
      domain: matches[5],
      pool: matches[6],
      region: matches[1],
      sha: {
        bootstrap: matches[8],
        disk: matches[7]
      }
    }));
  }

  render() {
    return (
      <li>
        <a href={'https://portal.azure.com/#@taskclusteraccountsmozilla.onmicrosoft.com/resource' + this.props.image} target="_blank">
          {this.state.region}
          -{this.state.domain}
          -{this.state.pool}
          -{this.state.sha.disk}
          -{this.state.sha.bootstrap}
        </a>
      </li>
    );
  }
}

export default Image;