import React from 'react'
import Image from './Image';

class Images extends React.Component {
  render() {
    return (
      <div>
        <span>worker manager image deployments:</span>
        <ul>
          {
            this.props.images.map(image => (
              <Image image={image} key={image} />
            ))
          }
        </ul>
      </div>
    );
  }
}

export default Images;