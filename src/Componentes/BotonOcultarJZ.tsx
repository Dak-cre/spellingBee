import { useState } from 'react';
import '../CSS/btn.css';

export const BotonOcultarJZ = () => {
  const [oculto, setOculto] = useState(false);

  return (
    <button
      type="button"
      onClick={() => setOculto((prev) => !prev)}
      className={`btn btn-ocultar-jz ${oculto ? 'btn-danger' : 'btn-outline-secondary'}`}
    >
      <i className={`bi ${oculto ? 'bi-eye-slash' : 'bi-eye'}`} />
      <span>{oculto ? 'Mostrar Juez' : 'Ocultar Juez'}</span>
    </button>
  );
};