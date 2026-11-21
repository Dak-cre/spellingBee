import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BotonOcultarJZ } from './Componentes/BotonOcultarJZ'
import 'bootstrap-icons/font/bootstrap-icons.css';



createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BotonOcultarJZ />
  </StrictMode>,
)